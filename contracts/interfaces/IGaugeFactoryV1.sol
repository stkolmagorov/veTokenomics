// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

import "./IVeHZV1.sol";
import "./IDistributorV1.sol";
import "./IGaugeV1.sol";

interface IGaugeFactoryV1 {
    error InvalidArrayLengths();

    event GaugeCreated(address indexed strategy, address indexed gauge);
    event EpochUpdated(uint256 indexed currentEpoch);
    event GaugeProcessed(address indexed gauge);
    event Multivoted(uint256 indexed tokenId, IGaugeV1[] indexed gauges, uint256[] indexed powers);
    event Multiunvoted(uint256 indexed tokenId, IGaugeV1[] indexed gauges, uint256[] indexed powers);

    /// @notice Initializes the contract.
    /// @param horiza_ Horiza contract address.
    /// @param veHZ_ veHZ contract address.
    /// @param distributor_ Distributor contract address.
    function initialize(address horiza_, IVeHZV1 veHZ_, IDistributorV1 distributor_) external;

    /// @notice Creates new gauge for strategy.
    /// @param strategy_ Strategy contract address.
    function createGauge(address strategy_) external;

    /// @notice Marks `gauge_` as processed in the current epoch.
    /// @param gauge_ Gauge contract address.
    function markGaugeAsProcessed(address gauge_) external;

    /// @notice Multivotes in gauges through token id.
    /// @param tokenId_ Voting token id.
    /// @param gauges_ Gauge contract addresses.
    /// @param powers_ Voting powers.
    function multivote(
        uint256 tokenId_, 
        IGaugeV1[] calldata gauges_, 
        uint256[] calldata powers_
    ) 
        external;
    
    /// @notice Multiunvotes from gauges through token id.
    /// @param tokenId_ Voting token id.
    /// @param gauges_ Gauge contract addresses.
    /// @param powers_ Voting powers.
    function multiunvote(
        uint256 tokenId_, 
        IGaugeV1[] calldata gauges_, 
        uint256[] calldata powers_
    ) 
        external;

    /// @notice Updates the epoch.
    function updateEpoch() external;

    /// @notice Retrieves existing gauges.
    /// @return Array of existing gauges.
    function getGauges() external view returns (IGaugeV1[] memory);

    /// @notice Retrieves the gauge by the Strategy contract address.
    /// @param strategy_ Strategy contract address.
    /// @return Gauge by the Strategy contract address.
    function gaugeByStrategy(address strategy_) external view returns (address);

    /// @notice Retrieves the boolean value indicating whether the gauge can be processed
    /// in the current epoch.
    /// @param gauge_ Gauge contract address.
    /// @return Boolean value indicating whether the gauge can be processed in the current epoch.
    function gaugeCanBeProcessed(address gauge_) external view returns (bool);

    /// @notice Retrieves the current epoch.
    /// @return Current epoch value.
    function currentEpoch() external view returns (uint256);
}