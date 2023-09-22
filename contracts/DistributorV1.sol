// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

import "./interfaces/IDistributorV1.sol";
import "./interfaces/IGaugeFactoryV1.sol";
import "./interfaces/IGaugeV1.sol";

contract DistributorV1 is 
    IDistributorV1, 
    Initializable, 
    UUPSUpgradeable, 
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    bytes32 public constant GAUGE_FACTORY_ROLE = keccak256("GAUGE_FACTORY_ROLE");

    // V1
    address public horiza;
    IGaugeFactoryV1 public gaugeFactory;
    EnumerableSetUpgradeable.AddressSet private _incentives;

    mapping(address => mapping(address => uint256)) public providedRewardByGaugeAndToken;

    /// @inheritdoc IDistributorV1
    function initialize(address horiza_, address gaugeFactory_) external initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        __ReentrancyGuard_init();
        horiza = horiza_;
        gaugeFactory = IGaugeFactoryV1(gaugeFactory_);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(GAUGE_FACTORY_ROLE, gaugeFactory_);
    }

    /// @inheritdoc IDistributorV1
    function addIncentives(address[] calldata incentives_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address m_horiza = horiza;
        for (uint256 i = 0; i < incentives_.length; ) {
            if (incentives_[i] == m_horiza) {
                revert HorizaTokenEntry(incentives_[i]);
            }
            if (!_incentives.add(incentives_[i])) {
                revert AlreadyAdded(incentives_[i]);
            }
            unchecked {
                i++;
            }
        }
        emit IncentivesAdded(incentives_);
    }

    /// @inheritdoc IDistributorV1
    function removeIncentives(address[] calldata incentives_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < incentives_.length; ) {
            if (!_incentives.remove(incentives_[i])) {
                revert NotFound(incentives_[i]);
            }
            unchecked {
                i++;
            }
        }
        emit IncentivesRemoved(incentives_);
    }

    /// @inheritdoc IDistributorV1
    function provideReward(address gauge_, address token_, uint256 reward_) external nonReentrant {
        if (!_incentives.contains(token_)) {
            revert InvalidRewardToken();
        }
        IERC20Upgradeable(token_).safeTransferFrom(msg.sender, address(this), reward_);
        unchecked {
            providedRewardByGaugeAndToken[gauge_][token_] += reward_;
        }
        emit RewardProvided(gauge_, token_, reward_);
    }

    /// @inheritdoc IDistributorV1
    function distributeRewards(IStrategy[] calldata strategies_) external nonReentrant {
        IGaugeFactoryV1 m_gaugeFactory = gaugeFactory;
        for (uint256 i = 0; i < strategies_.length; ) {
            IStrategy strategy = strategies_[i];
            address gauge = m_gaugeFactory.gaugeByStrategy(address(strategy));
            if (gauge == address(0)) {
                revert InvalidGauge(address(strategy));
            }
            if (m_gaugeFactory.gaugeCanBeProcessed(gauge)) {
                strategy.getAUMWithFees(true);
                strategy.claimFee();
                uint256 balance = strategy.balanceOf(address(this));
                uint256 fee0;
                uint256 fee1;
                if (balance > 0) {
                    (fee0, fee1) = strategy.burn(balance, 0, 0);
                }
                if (fee0 > 0) {
                    address token0 = IGaugeV1(gauge).token0();
                    IERC20Upgradeable(token0).safeTransfer(gauge, fee0);
                    IGaugeV1(gauge).provideReward(token0, fee0);
                }
                if (fee1 > 0) {
                    address token1 = IGaugeV1(gauge).token1();
                    IERC20Upgradeable(token1).safeTransfer(gauge, fee1);
                    IGaugeV1(gauge).provideReward(token1, fee1);
                }
                uint256 length = _incentives.length();
                for (uint256 j = 0; j < length; ) {
                    address incentive = _incentives.at(i);
                    uint256 reward = providedRewardByGaugeAndToken[gauge][incentive];
                    if (reward > 0) {
                        providedRewardByGaugeAndToken[gauge][incentive] = 0;
                        IERC20Upgradeable(incentive).safeTransfer(gauge, reward);
                        IGaugeV1(gauge).provideReward(incentive, reward);
                    }
                    unchecked {
                        j++;
                    }
                }
                m_gaugeFactory.markGaugeAsProcessed(gauge);
            }
            unchecked {
                i++;
            }
        }
    }

    /// @inheritdoc IDistributorV1
    function getIncentiveAt(uint256 index_) external view returns (address) {
        return _incentives.at(index_);
    }

    /// @inheritdoc IDistributorV1
    function getIncentivesLength() external view returns (uint256) {
        return _incentives.length();
    }

    /// @inheritdoc IDistributorV1
    function isIncentive(address token_) external view returns (bool) {
        return _incentives.contains(token_);
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}