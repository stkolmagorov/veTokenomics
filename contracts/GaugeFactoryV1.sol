// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "./GaugeV1.sol";

contract GaugeFactoryV1 is 
    IGaugeFactoryV1, 
    Initializable, 
    UUPSUpgradeable,
    AccessControlUpgradeable
{   
    using CountersUpgradeable for CountersUpgradeable.Counter;
    
    uint256 public constant EPOCH = 7 days;
    uint256 public constant SLIPPAGE_TIME = 5 minutes;
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");

    // V1
    uint256 currentEpochStartTime;
    address horiza;
    IVeHZV1 veHZ;
    IDistributorV1 distributor;
    CountersUpgradeable.Counter private _epoch;
    IGaugeV1[] public gauges;

    mapping(address => address) public gaugeByStrategy;
    mapping(address => mapping(uint256 => bool)) private _isGaugeProcessedByGaugeAndEpoch;

    /// @inheritdoc IGaugeFactoryV1
    function initialize(
        address horiza_,
        IVeHZV1 veHZ_,
        IDistributorV1 distributor_
    ) 
        external 
        initializer 
    {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        horiza = horiza_;
        veHZ = veHZ_;
        distributor = distributor_;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(DISTRIBUTOR_ROLE, address(distributor_));
    }

    /// @inheritdoc IGaugeFactoryV1
    function createGauge(address strategy_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address implementation = address(new GaugeV1());
        address gauge = address(new ERC1967Proxy(implementation, ""));
        IVeHZV1 m_veHZ = veHZ;
        IDistributorV1 m_distributor = distributor;
        IGaugeV1(gauge).initialize(
            msg.sender,
            IStrategy(strategy_).pool().token0(),
            IStrategy(strategy_).pool().token1(),
            horiza,
            strategy_,
            m_veHZ,
            m_distributor,
            IGaugeFactoryV1(this)
        );
        m_veHZ.grantGaugeRole(gauge);
        gaugeByStrategy[strategy_] = gauge;
        gauges.push(IGaugeV1(gauge));
        emit GaugeCreated(strategy_, gauge);
    }

    /// @inheritdoc IGaugeFactoryV1
    function markGaugeAsProcessed(address gauge_) external onlyRole(DISTRIBUTOR_ROLE) {
        _isGaugeProcessedByGaugeAndEpoch[gauge_][_epoch.current()] = true;
        emit GaugeProcessed(gauge_);
    }

    /// @inheritdoc IGaugeFactoryV1
    function multivote(
        uint256 tokenId_, 
        IGaugeV1[] calldata gauges_, 
        uint256[] calldata powers_
    ) 
        external 
    {
        if (gauges_.length != powers_.length) {
            revert InvalidArrayLengths();
        }
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId_;
        for (uint256 i = 0; i < gauges_.length; ) {
            uint256[] memory powers = new uint256[](1);
            powers[0] = powers_[i];
            gauges_[i].vote(tokenIds, powers);
            unchecked {
                i++;
            }
        }
        emit Multivoted(tokenId_, gauges_, powers_);
    }

    /// @inheritdoc IGaugeFactoryV1
    function multiunvote(
        uint256 tokenId_, 
        IGaugeV1[] calldata gauges_, 
        uint256[] calldata powers_
    ) 
        external 
    {
        if (gauges_.length != powers_.length) {
            revert InvalidArrayLengths();
        }
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId_;
        for (uint256 i = 0; i < gauges_.length; ) {
            uint256[] memory powers = new uint256[](1);
            powers[0] = powers_[i];
            gauges_[i].unvote(tokenIds, powers);
            unchecked {
                i++;
            }
        }
        emit Multiunvoted(tokenId_, gauges_, powers_);
    }

    /// @inheritdoc IGaugeFactoryV1
    function updateEpoch() external {
        uint256 elapsedTime = block.timestamp - currentEpochStartTime;
        if (elapsedTime >= EPOCH - SLIPPAGE_TIME) {
            _epoch.increment();
            emit EpochUpdated(_epoch.current());
        }
    }

    /// @inheritdoc IGaugeFactoryV1
    function gaugeCanBeProcessed(address gauge_) external view returns (bool) {
        return !_isGaugeProcessedByGaugeAndEpoch[gauge_][_epoch.current()];
    }

    /// @inheritdoc IGaugeFactoryV1
    function getGauges() external view returns (IGaugeV1[] memory) {
        return gauges;
    }

    /// @inheritdoc IGaugeFactoryV1
    function currentEpoch() external view returns (uint256) {
        return _epoch.current();
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}