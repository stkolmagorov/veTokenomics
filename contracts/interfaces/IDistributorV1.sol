// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "./IStrategy.sol";

interface IDistributorV1 {
    error HorizaTokenEntry(address token);
    error AlreadyAdded(address token);
    error NotFound(address token);
    error InvalidRewardToken();
    error InvalidGauge(address strategy);

    event IncentivesAdded(address[] indexed incentives);
    event IncentivesRemoved(address[] indexed incentives);
    event RewardProvided(address indexed gauge, address indexed token, uint256 indexed reward);
    event FeesProcessed(address indexed gauge, uint256 indexed fee0, uint256 indexed fee1);

    /// @notice Initializes the contract.
    /// @param horiza_ Horiza token contract address.
    /// @param gaugeFactory_ GaugeFactory contract address.
    function initialize(address horiza_, address gaugeFactory_) external;

    /// @notice Adds new incentive tokens.
    /// @param incentives_ Incentive token contract addresses.
    function addIncentives(address[] calldata incentives_) external;

    /// @notice Removes existing incentive tokens.
    /// @param incentives_ Incentive token contract addresses.
    function removeIncentives(address[] calldata incentives_) external;

    /// @notice Provides the reward to distribute for gauge.
    /// @param gauge_ Gauge contract address.
    /// @param token_ Token contract address.
    /// @param reward_ Reward amount.
    function provideReward(address gauge_, address token_, uint256 reward_) external;

    /// @notice Redirects all rewards to the gauge.
    /// @param strategies_ Strategy contract addresses.
    function distributeRewards(IStrategy[] calldata strategies_) external;

    /// @notice Retrieves the incentive token contract address by index.
    /// @param index_ Index value.
    /// @return Incentive token contract address.
    function getIncentiveAt(uint256 index_) external view returns (address);

    /// @notice Retrieves the incentive tokens length.
    /// @return Incentive tokens length.
    function getIncentivesLength() external view returns (uint256);

    /// @notice Retrieves the boolean value indicating whether the token is in incentive tokens list.
    /// @param token_ Token contract address.
    /// @return Boolean value indicating whether the token is in incentive tokens list.
    function isIncentive(address token_) external view returns (bool);
}