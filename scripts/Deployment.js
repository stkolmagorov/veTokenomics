const { ethers, upgrades } = require("hardhat");

async function main() {
    const Distributor = await ethers.getContractFactory("DistributorV1");
    const distributor = await upgrades.deployProxy(Distributor, [], { initializer: false, kind: "uups" });
    await distributor.waitForDeployment();
    console.log("Distributor deployed:", distributor.target);
    const GaugeFactory = await ethers.getContractFactory("GaugeFactoryV1");
    const gaugeFactory = await upgrades.deployProxy(GaugeFactory, [], { initializer: false, kind: "uups" });
    await gaugeFactory.waitForDeployment();
    console.log("Gauge factory deployed:", gaugeFactory.target);
    const VeHZ = await ethers.getContractFactory("VeHZV1");
    const veHZ = await upgrades.deployProxy(VeHZ, [], { initializer: false, kind: "uups" });
    await veHZ.waitForDeployment();
    console.log("Voting escrow deployed:", veHZ.target);
    const team = "0xb6c1a6393Ca3eE4aCa4B81112CAe61191D44cC34";
    const authority = "0xb6c1a6393Ca3eE4aCa4B81112CAe61191D44cC34";
    const Horiza = await ethers.getContractFactory("Horiza");
    const horiza = await Horiza.deploy(
        team,
        authority,
        veHZ.target,
        gaugeFactory.target
    );
    await horiza.waitForDeployment();
    console.log("Horiza token deployed:", horiza.target);
    let tx = await distributor.initialize(horiza.target, gaugeFactory.target);
    await tx.wait(5);
    console.log("Distributor initialized");
    tx = await gaugeFactory.initialize(horiza.target, veHZ.target, distributor.target);
    await tx.wait(5);
    console.log("Gauge factory initialized");
    tx = await veHZ.initialize(horiza.target, gaugeFactory.target);
    await tx.wait(5);
    console.log("Voting escrow initialized");
}
  
main().catch((error) => {
    console.error(error);
    process.exit(1);
});