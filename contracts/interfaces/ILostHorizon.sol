// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

interface ILostHorizon {
    error InvalidNumberOfTokens();
    error ForbiddenToMintMore();
    error InvalidMsgValue();
    error InvalidProof();

    event MerkleRootUpdated(bytes32 indexed oldMerkleRoot, bytes32 indexed newMerkleRoot);
    event TokenPriceUpdated(uint256 indexed oldTokenPrice, uint256 indexed newTokenPrice);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event AvailableNumberOfTokensToMintIncreased(
        uint256 indexed oldAvailableNumberOfTokensToMint, 
        uint256 indexed newAvailableNumberOfTokensToMint,
        uint256 indexed difference
    );
    event AvailableNumberOfTokensToMintDecreased(
        uint256 indexed oldAvailableNumberOfTokensToMint, 
        uint256 indexed newAvailableNumberOfTokensToMint,
        uint256 indexed difference
    );

    /// @notice Updates the Merkle tree root with whitelisted accounts.
    /// @param merkleRoot_ New Merkle tree root.
    function updateMerkleRoot(bytes32 merkleRoot_) external;

    /// @notice Updates the minting price per token.
    /// @param price_ New minting price per token.
    function updatePrice(uint256 price_) external;

    /// @notice Updates the treasury.
    /// @param treasury_ New treasury address.
    function updateTreasury(address payable treasury_) external;

    /// @notice Increases the available amount of tokens to mint.
    /// @param numberOfTokens_ Number of tokens to increase.
    function increaseAvailableNumberOfTokensToMint(uint256 numberOfTokens_) external;

    /// @notice Decreases the available amount of tokens to mint.
    /// @param numberOfTokens_ Number of tokens to decrease.
    function decreaseAvailableNumberOfTokensToMint(uint256 numberOfTokens_) external;

    /// @notice Withdraws payments for mint.
    function withdraw() external;

    /// @notice Mints `numberOfTokens_` tokens to `account_` for free.
    /// @param account_ Account address.
    /// @param numberOfTokens_ Number of tokens to mint.
    function reserve(address account_, uint256 numberOfTokens_) external;

    /// @notice Mints 1 token to the caller during private period.
    /// @param merkleProof_ Merkle tree proof for the caller.
    function privateMint(bytes32[] calldata merkleProof_) external payable;

    /// @notice Mints `numberOfTokens_` tokens to the caller during whitelist period.
    /// @param numberOfTokens_ Number of tokens to mint.
    /// @param merkleProof_ Merkle tree proof for the caller.
    function whitelistMint(uint256 numberOfTokens_, bytes32[] calldata merkleProof_) external payable;

    /// @notice Mints `numberOfTokens_` tokens to the caller during public period.
    /// @param numberOfTokens_ Number of tokens to mint.
    function publicMint(uint256 numberOfTokens_) external payable;
}