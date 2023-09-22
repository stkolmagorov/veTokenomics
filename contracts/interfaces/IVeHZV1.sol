// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "./IGaugeFactoryV1.sol";

interface IVeHZV1 {
    struct LockInfo {
        uint256 lockedAmount;
        uint256 initialPower;
        uint256 numberOfEpochsForLocking;
        uint256 genesisEpoch;
    }

    error IncorrectOwner(uint256 tokenId);
    error InvalidPower(uint256 power);
    error ZeroValueEntry();
    error InvalidNumberOfEpochsForLocking();
    error ForbiddenToUnlock();
    error NonExistentToken();
    error Expired();
    error InvalidNumberOfEpochsToExtend(uint256 actualNumberOfEpochs, uint256 availableNumberOfEpochs);
    error TokenIdsCannotBeEqual();
    error ForbiddenToTransferTokensWithUsedPower();

    event PowerIncreased(uint256 indexed tokenId, uint256 indexed added, uint256 indexed availablePower);
    event PowerDecreased(uint256 indexed tokenId, uint256 indexed subtracted, uint256 indexed availablePower);
    event Locked(address indexed creator, uint256 indexed tokenId);
    event Unlocked(address indexed unlocker, uint256 indexed tokenId, uint256 indexed lockedAmount);
    event Increased(uint256 indexed tokenId, uint256 indexed amount, uint256 indexed updatedLockedAmount);
    event Extended(uint256 indexed tokenId, uint256 indexed numberOfEpochs, uint256 indexed updatedNumberOfEpochsForLocking);
    event Merged(uint256 indexed tokenId0, uint256 indexed tokenId1, uint256 indexed mergerTokenId);
    
    /// @notice Initializes the contract.
    /// @param horiza_ Horiza contract address.
    /// @param gaugeFactory_ GaugeFactory contract address.
    function initialize(IERC20Upgradeable horiza_, IGaugeFactoryV1 gaugeFactory_) external;

    /// @notice Grants GAUGE_ROLE to `gauge_`.
    /// @param gauge_ Gauge contract address.
    function grantGaugeRole(address gauge_) external;

    /// @notice Increases the available voting power in the current epoch by token id.
    /// @param tokenIds_ Voting token ids.
    /// @param powers_ Voting powers.
    function increaseVotingPower(uint256[] calldata tokenIds_, uint256[] calldata powers_) external;

    /// @notice Decreases the available power in the current epoch by token id.
    /// @param account_ Account address.
    /// @param tokenIds_ Voting token ids.
    /// @param powers_ Voting powers.
    function decreaseVotingPower(address account_, uint256[] calldata tokenIds_, uint256[] calldata powers_) external;

    /// @notice Locks Horiza tokens and mints veHZ NFT to the lock creator.
    /// @param amount_ Amount of Horiza tokens to lock.
    /// @param numberOfEpochsForLocking_ Number of epochs for locking.
    function lock(uint256 amount_, uint256 numberOfEpochsForLocking_) external;

    /// @notice Unlocks Horiza tokens.
    /// @param tokenIds_ Lock token ids.
    function unlock(uint256[] calldata tokenIds_) external;

    /// @notice Increases locked amount and voting power by token id.
    /// @param tokenId_ Token id.
    /// @param amount_ Amount of Horiza tokens to lock.
    function increase(uint256 tokenId_, uint256 amount_) external;

    /// @notice Extends lock duration by token id.
    /// @param tokenId_ Token id.
    /// @param numberOfEpochs_ Additional number of epochs for locking.
    function extend(uint256 tokenId_, uint256 numberOfEpochs_) external;

    /// @notice Merges `tokenId0_` and `tokenId1_` locks and burns this lock in exchange for a new lock.
    /// @param tokenId0_ First token id to merge.
    /// @param tokenId1_ Second token id to merge.
    function merge(uint256 tokenId0_, uint256 tokenId1_) external;

    /// @notice Retrieves the amount of total locked Horiza tokens.
    /// @return Amount of total locked Horiza tokens.
    function totalLocked() external view returns (uint256);

    /// @notice Retrieves the number of token holders.
    /// @return Number of token holders.
    function numberOfHolders() external view returns (uint256);

    /// @notice Retrieves the token holder by index.
    /// @param index_ Index value.
    /// @return Token holder by index.
    function getHolderAt(uint256 index_) external view returns (address);

    /// @notice Retrieves the total voting power by token id in the current epoch.
    /// @param tokenId_ Token id.
    /// @return Total voting power by token id in the current epoch.
    function totalPowerByTokenId(uint256 tokenId_) external view returns (uint256);

    /// @notice Retrieves the available voting power by token id in the current epoch.
    /// @param tokenId_ Token id.
    /// @return Available voting power by token id in the current epoch.
    function availablePowerByTokenId(uint256 tokenId_) external view returns (uint256);

    /// @notice Retrieves the number of remaining epochs by token id.
    /// @param tokenId_ Lock token id.
    /// @return Number of remaining epochs by token id.
    function numberOfRemainingEpochsByTokenId(uint256 tokenId_) external view returns (uint256);
}