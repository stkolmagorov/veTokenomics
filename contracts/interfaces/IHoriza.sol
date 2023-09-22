// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

interface IHoriza {
    error ForbiddenToUpdateMerkleRoot();
    error EmptyGaugesArray();
    error MerkleRootWasUpdated();
    error InvalidProof();
    error NothingToClaim();

    event MerkleRootUpdated(bytes32 indexed oldMerkleRoot, bytes32 indexed newMerkleRoot, uint256 indexed forEpoch);
    event EmissionDistributed(uint256 indexed emission, uint256 indexed epoch);
    event Claimed(address indexed account, uint256 indexed reward);

    /// @notice Updates the Merkle tree root to reward veHZ holders.
    /// @param merkleRoot_ New Merkle tree root.
    function updateMerkleRoot(bytes32 merkleRoot_) external;

    /// @notice Distributes emission every epoch (2% to the team, up to 30% to veHZ holders, up to 98% to liqiudity providers).
    function distributeEmission() external;

    /// @notice Transfers the earned reward to veHZ holders.
    /// @param account_ Reward recipient account address.
    /// @param cumulativeEarnedEmission_ Cumulative earned emission by `account_`.
    /// @param expectedMerkleRoot_ Expected Merkle root (most recent).
    /// @param merkleProof_ Merkle proof for `account_`.
    function claim(
        address account_,
        uint256 cumulativeEarnedEmission_,
        bytes32 expectedMerkleRoot_,
        bytes32[] calldata merkleProof_
    ) 
        external;
}