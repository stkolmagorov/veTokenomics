// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import "./interfaces/IHoriza.sol";
import "./interfaces/IGaugeFactoryV1.sol";

contract Horiza is IHoriza, ERC20, AccessControl {
    using SafeERC20 for IERC20;

    uint256 public constant INITIAL_SUPPLY = 50_000_000 ether;
    uint256 public constant INITIAL_WEEKLY_EMMISSION = 2_600_000 ether;
    uint256 public constant MAXIMUM_EMISSION_EPOCHS = 260;
    uint256 public constant EMISSION_DECAY_PERCENTAGE = 1;
    uint256 public constant EMISSION_PERCENTAGE_FOR_TEAM = 2;
    uint256 public constant EMISSION_PERCENTAGE_FOR_LIQUIDITY_PROVIDERS = 68;
    uint256 public constant EMISSION_PERCENTAGE_FOR_VE_HZ_HOLDERS = 30;
    uint256 public constant BASE_PERCENTAGE = 100;
    bytes32 public constant AUTHORITY_ROLE = keccak256("AUTHORITY_ROLE");

    address public immutable team;
    uint256 public emissionForThePreviousEpoch;
    uint256 public cumulativeEmissionForVeHZHolders;
    uint256 public storedEmissionForLiquidityProviders;
    bytes32 public merkleRoot;
    IVeHZV1 public immutable veHZ;
    IGaugeFactoryV1 public immutable gaugeFactory;

    mapping(uint256 => bool) public isMerkleRootSetByEpoch;
    mapping(uint256 => bool) public isEmissionDistributedByEpoch;
    mapping(address => uint256) public cumulativeClaimedEmissionByAccount;

    /// @param team_ Team address.
    /// @param authority_ Authorised address.
    /// @param veHZ_ veHZ contract address.
    /// @param gaugeFactory_ GaugeFactory contract address.
    constructor(
        address team_,
        address authority_,
        IVeHZV1 veHZ_,
        IGaugeFactoryV1 gaugeFactory_
    ) 
        ERC20("Horiza", "HZ")
    {
        team = team_;
        veHZ = veHZ_;
        gaugeFactory = gaugeFactory_;
        _mint(team_, INITIAL_SUPPLY);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(AUTHORITY_ROLE, authority_);
    }

    /// @inheritdoc IHoriza
    function updateMerkleRoot(bytes32 merkleRoot_) external onlyRole(AUTHORITY_ROLE) {
        uint256 m_currentEpoch = gaugeFactory.currentEpoch();
        if (
            isMerkleRootSetByEpoch[m_currentEpoch] 
            || m_currentEpoch == 0 
            || m_currentEpoch > MAXIMUM_EMISSION_EPOCHS
        ) {
            revert ForbiddenToUpdateMerkleRoot();
        }
        unchecked {
            emit MerkleRootUpdated(merkleRoot, merkleRoot_, m_currentEpoch - 1);
        }
        merkleRoot = merkleRoot_;
    }

    /// @inheritdoc IHoriza
    function distributeEmission() external {
        uint256 m_currentEpoch = gaugeFactory.currentEpoch();
        if (
            !isEmissionDistributedByEpoch[m_currentEpoch] 
            && m_currentEpoch < MAXIMUM_EMISSION_EPOCHS 
            && m_currentEpoch > 0
        ) {
            isEmissionDistributedByEpoch[m_currentEpoch] = true;
            uint256 emission;
            if (m_currentEpoch == 1) {
                emission = INITIAL_WEEKLY_EMMISSION;
            } else {
                unchecked {
                    emission = 
                        emissionForThePreviousEpoch 
                        * (BASE_PERCENTAGE - EMISSION_DECAY_PERCENTAGE) 
                        / BASE_PERCENTAGE;
                }
            }
            unchecked {
                uint256 emissionForTeam 
                    = emission * EMISSION_PERCENTAGE_FOR_TEAM / BASE_PERCENTAGE;
                _mint(team, emissionForTeam);
                uint256 expectedEmissionForVeHZHolders = 
                    emission 
                    * EMISSION_PERCENTAGE_FOR_VE_HZ_HOLDERS 
                    / BASE_PERCENTAGE;
                uint256 actualEmissionForVeHZHolders = 
                    expectedEmissionForVeHZHolders 
                    * veHZ.totalLocked()
                    / totalSupply();
                _mint(address(this), actualEmissionForVeHZHolders);
                cumulativeEmissionForVeHZHolders += actualEmissionForVeHZHolders;
                IGaugeV1[] memory gauges = gaugeFactory.getGauges();
                if (gauges.length == 0) {
                    revert EmptyGaugesArray();
                }
                uint256[] memory powerByGauge = new uint256[](gauges.length);
                uint256 totalPower;
                for (uint256 i = 0; i < gauges.length; i++) {
                    uint256 power = gauges[i].totalPowerByEpoch(m_currentEpoch - 1);
                    powerByGauge[i] += power;
                    totalPower += power;
                }
                uint256 emissionForLiquidityProviders = 
                    emission 
                    * EMISSION_PERCENTAGE_FOR_LIQUIDITY_PROVIDERS 
                    / BASE_PERCENTAGE 
                    + (expectedEmissionForVeHZHolders - actualEmissionForVeHZHolders);
                uint256 totalEmissionForLiquidityProviders = emissionForLiquidityProviders + storedEmissionForLiquidityProviders;
                if (totalPower > 0) {
                    for (uint256 i = 0; i < gauges.length; i++) {
                        uint256 emissionForGauge = totalEmissionForLiquidityProviders * powerByGauge[i] / totalPower;
                        _mint(address(gauges[i]), emissionForGauge);
                        gauges[i].provideReward(address(this), emissionForGauge);
                    }
                    storedEmissionForLiquidityProviders = 0;
                } else {
                    storedEmissionForLiquidityProviders += emissionForLiquidityProviders;
                }
            }
            emissionForThePreviousEpoch = emission;
            emit EmissionDistributed(emission, m_currentEpoch);
        }
    }

    /// @inheritdoc IHoriza
    function claim(
        address account_,
        uint256 cumulativeEarnedEmission_,
        bytes32 expectedMerkleRoot_,
        bytes32[] calldata merkleProof_
    ) 
        external
    {
        bytes32 m_merkleRoot = merkleRoot;
        if (m_merkleRoot != expectedMerkleRoot_) {
            revert MerkleRootWasUpdated();
        }
        bytes32 leaf = keccak256(abi.encodePacked(account_, cumulativeEarnedEmission_));
        if (!MerkleProof.verifyCalldata(merkleProof_, m_merkleRoot, leaf)) {
            revert InvalidProof();
        }
        uint256 reward = cumulativeEarnedEmission_ - cumulativeClaimedEmissionByAccount[account_];
        if (reward == 0) {
            revert NothingToClaim();
        }
        cumulativeClaimedEmissionByAccount[account_] = cumulativeEarnedEmission_;
        _transfer(address(this), account_, reward);
        emit Claimed(account_, reward);
    }
}