const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const { loadFixture, time } = require("@nomicfoundation/hardhat-network-helpers");
const { MerkleTree } = require("merkletreejs");

describe("Main flow test (integrational)", () => {
    const ONE_WEEK = 604800n;
    const INITIAL_SUPPLY = ethers.parseEther("50000000");
    const LOCK_AMOUNT = ethers.parseEther("100000");
    const INITIAL_WEEKLY_EMMISSION = ethers.parseEther("2600000");
    const POWER_INCREASE_PERCENTAGE = 9615n;
    const BASE_PERCENTAGE = 1000000n; 
    const STRATEGY = "0x3D6f08ae8C2931E27e95811E42F5d70164759a94";

    before(async () => {
        [owner, team, authority] = await ethers.getSigners();
    });

    const fixture = async () => {
        const Distributor = await ethers.getContractFactory("DistributorV1");
        const distributorInstance = await upgrades.deployProxy(Distributor, [], { initializer: false, kind: "uups" });
        const GaugeFactory = await ethers.getContractFactory("GaugeFactoryV1");
        const gaugeFactoryInstance = await upgrades.deployProxy(GaugeFactory, [], { initializer: false, kind: "uups" });
        const VeHZ = await ethers.getContractFactory("VeHZV1");
        const veHZInstance = await upgrades.deployProxy(VeHZ, [], { initializer: false, kind: "uups" });
        const Horiza = await ethers.getContractFactory("Horiza");
        const horizaInstance = await Horiza.deploy(
            team.address,
            authority.address,
            veHZInstance.target,
            gaugeFactoryInstance.target
        );
        await horizaInstance.connect(team).transfer(owner.address, INITIAL_SUPPLY);
        await distributorInstance.initialize(horizaInstance.target, gaugeFactoryInstance.target);
        await gaugeFactoryInstance.initialize(horizaInstance.target, veHZInstance.target, distributorInstance.target);
        await veHZInstance.initialize(horizaInstance.target, gaugeFactoryInstance.target);
        return { distributorInstance, gaugeFactoryInstance, veHZInstance, horizaInstance };
    }

    beforeEach(async () => {
        const { distributorInstance, gaugeFactoryInstance, veHZInstance, horizaInstance } = await loadFixture(fixture);
        distributor = distributorInstance;
        gaugeFactory = gaugeFactoryInstance;
        veHZ = veHZInstance;
        horiza = horizaInstance;
    });

    it("Successful Horiza contract logic execution", async () => {
        // Gauge creating
        await gaugeFactory.createGauge(STRATEGY);
        // + 1 epoch
        await time.increase(ONE_WEEK);
        await gaugeFactory.updateEpoch();
        // Emission distribution
        await horiza.distributeEmission();
        expect(await horiza.emissionForThePreviousEpoch()).to.equal(INITIAL_WEEKLY_EMMISSION);
        expect(await horiza.storedEmissionForLiquidityProviders()).to.equal(INITIAL_WEEKLY_EMMISSION * 98n / 100n);
        // Lock creation
        await horiza.approve(veHZ.target, LOCK_AMOUNT);
        await veHZ.lock(LOCK_AMOUNT, 104);
        // Voting in the gauge
        const gauge = await ethers.getContractAt("GaugeV1", await gaugeFactory.gaugeByStrategy(STRATEGY));
        await gauge.vote([1], [100]);
        // + 1 epoch
        await time.increase(ONE_WEEK);
        await gaugeFactory.updateEpoch();
        // Emission distribution
        await horiza.distributeEmission();
        expect(await horiza.emissionForThePreviousEpoch()).to.equal(INITIAL_WEEKLY_EMMISSION * 99n / 100n);
        expect(await horiza.storedEmissionForLiquidityProviders()).to.equal(0);
        expect(await horiza.cumulativeEmissionForVeHZHolders()).to.be.gt(0);
        expect(await horiza.balanceOf(team.address)).to.be.gt(0);
        expect(await gauge.rewardRate()).to.be.gt(0);
        // New lock creating
        await horiza.transfer(authority.address, LOCK_AMOUNT / 2n);
        await horiza.connect(authority).approve(veHZ.target, LOCK_AMOUNT / 2n);
        await veHZ.connect(authority).lock(LOCK_AMOUNT / 2n, 104);
        // Merkle tree generation
        const cumulativeEmissionForVeHZHolders = await horiza.cumulativeEmissionForVeHZHolders();
        const totalLocked = await veHZ.totalLocked();
        const numberOfHolders = await veHZ.numberOfHolders();
        const holders = [];
        const shareByHolder = new Map();
        for (let i = 0; i < numberOfHolders; i++) {
            const holder = await veHZ.getHolderAt(i);
            holders.push(holder);
            const balance = await veHZ.balanceOf(holder);
            let lockedAmount = 0n;
            for (let j = 0; j < balance; j++) {
                lockedAmount += (await veHZ.lockInfoByTokenId(await veHZ.tokenOfOwnerByIndex(holder, j))).lockedAmount;
            }
            shareByHolder.set(holder, lockedAmount * cumulativeEmissionForVeHZHolders / totalLocked);
        }
        const elements = holders.map((holder) => 
            holder
            + ethers.zeroPadValue(ethers.toBeHex(shareByHolder.get(holder)), 32).substring(2)
        );
        let hashedElements = [];
        for (let element of elements) {
            hashedElements.push(ethers.keccak256(element));
        }
        const tree = new MerkleTree(elements, ethers.keccak256, { hashLeaves: true, sort: true });
        const root = tree.getHexRoot();
        await horiza.connect(authority).updateMerkleRoot(root);
        // Reward claiming
        const leaves = tree.getHexLeaves();
        const proofs = leaves.map(tree.getHexProof, tree);
        await horiza.connect(authority).claim(
            authority.address,
            shareByHolder.get(authority.address),
            await horiza.merkleRoot(),
            proofs[leaves.indexOf(hashedElements[1])]
        );
        expect(await horiza.balanceOf(authority.address)).to.equal(shareByHolder.get(authority.address));
    });

    it("Successful VeHZ contract logic execution", async () => {
        // Lock creation
        await horiza.approve(veHZ.target, LOCK_AMOUNT);
        await veHZ.lock(LOCK_AMOUNT, 104);
        expect(await veHZ.balanceOf(owner.address)).to.equal(1);
        expect(await veHZ.totalPowerByTokenId(1)).to.equal(LOCK_AMOUNT);
        expect(await veHZ.numberOfRemainingEpochsByTokenId(1)).to.equal(104);
        expect(await veHZ.numberOfHolders()).to.equal(1);
        expect(await veHZ.getHolderAt(0)).to.equal(owner.address);
        // Unlocking attempt
        await expect(veHZ.unlock([1])).to.be.revertedWithCustomError(veHZ, "ForbiddenToUnlock");
        // Extending attempt
        await expect(veHZ.extend(1, 1)).to.be.revertedWithCustomError(veHZ, "InvalidNumberOfEpochsToExtend");
        // Successful increasing
        await horiza.approve(veHZ.target, LOCK_AMOUNT);
        await veHZ.increase(1, LOCK_AMOUNT);
        expect(await veHZ.totalPowerByTokenId(1)).to.equal(LOCK_AMOUNT * 2n);
        expect(await veHZ.availablePowerByTokenId(1)).to.equal(LOCK_AMOUNT * 2n);
        expect(await veHZ.totalLocked()).to.equal(LOCK_AMOUNT * 2n);
        // + 1 epoch
        await time.increase(ONE_WEEK);
        await gaugeFactory.updateEpoch();
        expect(await veHZ.totalPowerByTokenId(1))
            .to.equal(LOCK_AMOUNT * 2n * (BASE_PERCENTAGE - POWER_INCREASE_PERCENTAGE) / BASE_PERCENTAGE);
        expect(await veHZ.availablePowerByTokenId(1))
            .to.equal(LOCK_AMOUNT * 2n * (BASE_PERCENTAGE - POWER_INCREASE_PERCENTAGE) / BASE_PERCENTAGE);
        // Successful extending
        await veHZ.extend(1, 1);
        expect(await veHZ.numberOfRemainingEpochsByTokenId(1)).to.equal(104);
        expect(await veHZ.totalPowerByTokenId(1)).to.equal(LOCK_AMOUNT * 2n);
        expect(await veHZ.availablePowerByTokenId(1)).to.equal(LOCK_AMOUNT * 2n);
        // New lock creation
        await horiza.approve(veHZ.target, LOCK_AMOUNT);
        await veHZ.lock(LOCK_AMOUNT, 30);
        expect(await veHZ.balanceOf(owner.address)).to.equal(2);
        expect(await veHZ.totalPowerByTokenId(2)).to.equal(LOCK_AMOUNT * 30n * POWER_INCREASE_PERCENTAGE / BASE_PERCENTAGE);
        expect(await veHZ.numberOfRemainingEpochsByTokenId(2)).to.equal(30);
        expect(await veHZ.numberOfHolders()).to.equal(1);
        // Successful merging
        await veHZ.merge(1, 2);
        expect(await veHZ.numberOfHolders()).to.equal(1);
        expect(await veHZ.getHolderAt(0)).to.equal(owner.address);
        expect(await veHZ.balanceOf(owner.address)).to.equal(1);
        expect(await veHZ.totalPowerByTokenId(3)).to.equal(LOCK_AMOUNT * 3n);
        expect(await veHZ.availablePowerByTokenId(3)).to.equal(LOCK_AMOUNT * 3n);
        expect(await veHZ.numberOfRemainingEpochsByTokenId(3)).to.equal(104);
    });
});