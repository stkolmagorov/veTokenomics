// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "./IVeHZV1.sol";
import "./IDistributorV1.sol";
import "./IGaugeFactoryV1.sol";

interface IGaugeV1 {
    error ProvidedRewardTooHigh();
    error InvalidRewardToken(address token);
    error InvalidArrayLengths();
    error IncorrectOwner(uint256 tokenId);

    event Staked(address indexed account, uint256 indexed amount);
    event Voted(address indexed account, uint256[] indexed tokenIds, uint256[] indexed powers);
    event Unstaked(address indexed account, uint256 indexed amount);
    event Unvoted(address indexed account, uint256[] indexed tokenIds, uint256[] indexed powers);
    event Claimed(address indexed account, address indexed token, uint256 indexed reward);
    event RewardProvided(address indexed token, uint256 indexed reward);

    /// @notice Initializes the contract.
    /// @param admin_ Contract admin address.
    /// @param token0_ Token0 contract address.
    /// @param token1_ Token1 contract address.
    /// @param horiza_ Horiza contract address.
    /// @param deShare_ Strategy contract address.
    /// @param veHZ_ veHZ contract address.
    /// @param distributor_ Distributor contract address.
    /// @param gaugeFactory_ GaugeFactory contract address.
    function initialize(
        address admin_,
        address token0_,
        address token1_,
        address horiza_,
        address deShare_,
        IVeHZV1 veHZ_,
        IDistributorV1 distributor_,
        IGaugeFactoryV1 gaugeFactory_
    ) 
        external;
    
    /// @notice Provides reward for `token_` reward token.
    /// @param token_ Token contract address.
    /// @param reward_ Reward amount.
    function provideReward(address token_, uint256 reward_) external;

    /// @notice Stakes DEShare tokens.
    /// @param amount_ Amount of tokens to stake.
    function stake(uint256 amount_) external;

    /// @notice Votes via veHZ tokens.
    /// @param tokenIds_ Voting token ids.
    /// @param powers_ Voting powers.
    function vote(uint256[] calldata tokenIds_, uint256[] calldata powers_) external;

    /// @notice Unstakes/unvotes all the caller's tokens/powers.
    /// @param forVoter_ Boolean value indicating whether to proceed the operation for a voter.
    function exit(bool forVoter_) external;

    /// @notice Unstakes DEShare tokens.
    /// @param amount_ Amount of tokens to unstake.
    function unstake(uint256 amount_) external;

    /// @notice Unvotes via veHZ tokens.
    /// @param tokenIds_ Voting token ids.
    /// @param powers_ Voting powers.
    function unvote(uint256[] memory tokenIds_, uint256[] calldata powers_) external;

    /// @notice Gets the earned reward for caller.
    /// @param forVoter_ Boolean value indicating whether to proceed the operation for a voter.
    function claim(bool forVoter_) external;

    /// @notice Retrieves the total power by epoch.
    /// @param epoch_ Epoch.
    /// @return Total power by epoch.
    function totalPowerByEpoch(uint256 epoch_) external view returns (uint256);

    /// @notice Retrieves voting token ids by `account_` in the current epoch.
    /// @param account_ Account address.
    /// @param index_ Index value.
    /// @return Voting token id by `account_` in the current epoch.
    function getTokenIdByAccountAndCurrentEpochAt(address account_, uint256 index_) external view returns (uint256);

    /// @notice Retrieves the number of voting tokens by `account_` in the current epoch.
    /// @param account_ Account address.
    /// @return Number of voting tokens by `account_` in the current epoch.
    function getTokenIdsLengthByAccountAndCurrentEpoch(address account_) external view returns (uint256);

    /// @notice Retrieves the last time reward was applicable for Horiza token.
    /// @return Last time reward was applicable for Horiza token.
    function lastTimeRewardApplicable() external view returns (uint256);

    /// @notice Retrieves the reward per token amount for Horiza token.
    /// @return Reward per token amount for Horiza token.
    function rewardPerToken() external view returns (uint256);

    /// @notice Retrieves the earned reward amount by staker.
    /// @param account_ Account address.
    /// @return Earned reward amount by staker.
    function earnedByStaker(address account_) external view returns (uint256);

    /// @notice Retrieves the earned reward amount by voter.
    /// @param account_ Account address.
    /// @param token_ Reward token address.
    /// @param startEpoch_ Epoch from which the reward is to be calculated.
    /// @param endEpoch_ Epoch to which the reward is to be calculated.
    /// @return Earned reward amount by voter.
    function earnedByVoter(
        address account_, 
        address token_, 
        uint256 startEpoch_, 
        uint256 endEpoch_
    ) 
        external 
        view 
        returns (uint256);

    /// @notice Retrieves token0 storage variable.
    /// @return Storage variable.
    function token0() external view returns (address);

    /// @notice Retrieves token1 storage variable.
    /// @return Storage variable.
    function token1() external view returns (address);
}