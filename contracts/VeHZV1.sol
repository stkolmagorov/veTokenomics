// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

import "./interfaces/IVeHZV1.sol";

contract VeHZV1 is 
    IVeHZV1, 
    Initializable, 
    UUPSUpgradeable, 
    ERC721EnumerableUpgradeable, 
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using CountersUpgradeable for CountersUpgradeable.Counter;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    uint256 public constant MAXIMUM_NUMBER_OF_EPOCHS_FOR_LOCKING = 104;
    uint256 public constant POWER_INCREASE_PERCENTAGE = 9615;
    uint256 public constant BASE_PERCENTAGE = 1000000; 
    bytes32 public constant GAUGE_FACTORY_ROLE = keccak256("GAUGE_FACTORY_ROLE");
    bytes32 public constant GAUGE_ROLE = keccak256("GAUGE_ROLE");

    // V1
    uint256 public totalLocked;
    IERC20Upgradeable public horiza;
    IGaugeFactoryV1 public gaugeFactory;
    CountersUpgradeable.Counter private _tokenId;
    EnumerableSetUpgradeable.AddressSet private _holders;

    mapping(uint256 => LockInfo) public lockInfoByTokenId;
    mapping(uint256 => mapping(uint256 => uint256)) public usedPowerByTokenIdAndEpoch;

    /// @inheritdoc IVeHZV1
    function initialize(IERC20Upgradeable horiza_, IGaugeFactoryV1 gaugeFactory_) external initializer {
        __UUPSUpgradeable_init();
        __ERC721_init("veHoriza", "veHZ");
        __ERC721Enumerable_init();
        __AccessControl_init();
        __ReentrancyGuard_init();
        horiza = horiza_;
        gaugeFactory = gaugeFactory_;
        _tokenId.increment();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(GAUGE_FACTORY_ROLE, address(gaugeFactory_));
    }

    /// @inheritdoc IVeHZV1
    function grantGaugeRole(address gauge_) external onlyRole(GAUGE_FACTORY_ROLE) {
        _grantRole(GAUGE_ROLE, gauge_);
    }

    /// @inheritdoc IVeHZV1
    function increaseVotingPower(
        uint256[] calldata tokenIds_, 
        uint256[] calldata powers_
    ) 
        external 
        onlyRole(GAUGE_ROLE) 
    {
        for (uint256 i = 0; i < tokenIds_.length; ) {
            if (powers_[i] == 0) {
                revert InvalidPower(powers_[i]);
            }
            usedPowerByTokenIdAndEpoch[tokenIds_[i]][gaugeFactory.currentEpoch()] -= powers_[i];
            unchecked {
                emit PowerIncreased(
                    tokenIds_[i], 
                    powers_[i], 
                    availablePowerByTokenId(tokenIds_[i]) + powers_[i]
                );
                i++;
            }
        }
    }

    /// @inheritdoc IVeHZV1
    function decreaseVotingPower(
        address account_, 
        uint256[] calldata tokenIds_, 
        uint256[] calldata powers_
    ) 
        external 
        onlyRole(GAUGE_ROLE) 
    {
        for (uint256 i = 0; i < tokenIds_.length; ) {
            if (ownerOf(tokenIds_[i]) != account_) {
                revert IncorrectOwner(tokenIds_[i]);
            }
            uint256 m_currentEpoch = gaugeFactory.currentEpoch();
            uint256 availablePower = availablePowerByTokenId(tokenIds_[i]);
            if (powers_[i] == 0 || powers_[i] > availablePower) {
                revert InvalidPower(powers_[i]);
            }
            unchecked {
                usedPowerByTokenIdAndEpoch[tokenIds_[i]][m_currentEpoch] += powers_[i];
                emit PowerDecreased(tokenIds_[i], powers_[i], availablePower - powers_[i]);
                i++;
            }
        }
    }

    /// @inheritdoc IVeHZV1
    function lock(uint256 amount_, uint256 numberOfEpochsForLocking_) external nonReentrant {
        if (amount_ == 0) {
            revert ZeroValueEntry();
        }
        if (
            numberOfEpochsForLocking_ == 0 
            || numberOfEpochsForLocking_ > MAXIMUM_NUMBER_OF_EPOCHS_FOR_LOCKING
        ) {
            revert InvalidNumberOfEpochsForLocking();
        }
        horiza.safeTransferFrom(msg.sender, address(this), amount_);
        unchecked {
            totalLocked += amount_;
        }
        uint256 initialPower;
        if (numberOfEpochsForLocking_ == MAXIMUM_NUMBER_OF_EPOCHS_FOR_LOCKING) {
            initialPower = amount_;
        } else {
            unchecked {
                initialPower = 
                    amount_ 
                    * numberOfEpochsForLocking_ 
                    * POWER_INCREASE_PERCENTAGE 
                    / BASE_PERCENTAGE;
            }
        }
        uint256 tokenId = _tokenId.current();
        lockInfoByTokenId[tokenId] = LockInfo(
            amount_, 
            initialPower,
            numberOfEpochsForLocking_, 
            gaugeFactory.currentEpoch()
        );
        _safeMint(msg.sender, tokenId);
        _tokenId.increment();
        if (!_holders.contains(msg.sender)) {
            _holders.add(msg.sender);
        }
        emit Locked(msg.sender, tokenId);
    }

    /// @inheritdoc IVeHZV1
    function unlock(uint256[] calldata tokenIds_) external nonReentrant {
        for (uint256 i = 0; i < tokenIds_.length; ) {
            if (ownerOf(tokenIds_[i]) != msg.sender) {
                revert IncorrectOwner(tokenIds_[i]);
            }
            LockInfo storage lockInfo = lockInfoByTokenId[tokenIds_[i]];
            uint256 numberOfPassedEpochs = gaugeFactory.currentEpoch() - lockInfo.genesisEpoch;
            uint256 lockedAmount = lockInfo.lockedAmount;
            if (lockInfo.numberOfEpochsForLocking <= numberOfPassedEpochs && lockedAmount > 0) {
                horiza.safeTransfer(msg.sender, lockedAmount);
                totalLocked -= lockedAmount;
                delete lockInfoByTokenId[tokenIds_[i]];
                _burn(tokenIds_[i]);
                emit Unlocked(msg.sender, tokenIds_[i], lockedAmount);
            } else {
                revert ForbiddenToUnlock();
            }
            unchecked {
                i++;
            }
        }
    }

    /// @inheritdoc IVeHZV1
    function increase(uint256 tokenId_, uint256 amount_) external nonReentrant {
        if (ownerOf(tokenId_) != msg.sender) {
            revert IncorrectOwner(tokenId_);
        }
        LockInfo storage lockInfo = lockInfoByTokenId[tokenId_];
        uint256 numberOfPassedEpochs;
        unchecked {
            numberOfPassedEpochs = gaugeFactory.currentEpoch() - lockInfo.genesisEpoch;
        }
        if (numberOfPassedEpochs >= lockInfo.numberOfEpochsForLocking) {
            revert Expired();
        }
        if (amount_ == 0) {
            revert ZeroValueEntry();
        }
        horiza.safeTransferFrom(msg.sender, address(this), amount_);
        unchecked {
            totalLocked += amount_;
        }
        uint256 updatedLockedAmount;
        unchecked {
            updatedLockedAmount = lockInfo.lockedAmount + amount_;
        }
        lockInfo.lockedAmount = updatedLockedAmount;
        uint256 m_numberOfEpochsForLocking = lockInfo.numberOfEpochsForLocking;
        uint256 updatedInitialPower;
        if (m_numberOfEpochsForLocking == MAXIMUM_NUMBER_OF_EPOCHS_FOR_LOCKING) {
            updatedInitialPower = updatedLockedAmount;
        } else {
            unchecked {
                updatedInitialPower = 
                    updatedLockedAmount 
                    * m_numberOfEpochsForLocking 
                    * POWER_INCREASE_PERCENTAGE 
                    / BASE_PERCENTAGE;
            }
        }
        lockInfo.initialPower = updatedInitialPower;
        emit Increased(tokenId_, amount_, updatedLockedAmount);
    }

    /// @inheritdoc IVeHZV1
    function extend(uint256 tokenId_, uint256 numberOfEpochs_) external {
        if (ownerOf(tokenId_) != msg.sender) {
            revert IncorrectOwner(tokenId_);
        }
        if (numberOfEpochs_ == 0) {
            revert ZeroValueEntry();
        }
        LockInfo storage lockInfo = lockInfoByTokenId[tokenId_];
        uint256 m_currentEpoch = gaugeFactory.currentEpoch();
        uint256 numberOfPassedEpochs;
        unchecked {
            numberOfPassedEpochs = m_currentEpoch - lockInfo.genesisEpoch;
        }
        uint256 m_numberOfEpochsForLocking = lockInfo.numberOfEpochsForLocking;
        uint256 availableNumberOfEpochs;
        if (numberOfPassedEpochs >= m_numberOfEpochsForLocking) {
            availableNumberOfEpochs = MAXIMUM_NUMBER_OF_EPOCHS_FOR_LOCKING;
        } else {
            unchecked {
                availableNumberOfEpochs = 
                    MAXIMUM_NUMBER_OF_EPOCHS_FOR_LOCKING 
                    - (m_numberOfEpochsForLocking - numberOfPassedEpochs);
            }
        }
        if (numberOfEpochs_ > availableNumberOfEpochs) {
            revert InvalidNumberOfEpochsToExtend(numberOfEpochs_, availableNumberOfEpochs);
        }
        unchecked {
            if (m_numberOfEpochsForLocking + numberOfEpochs_ > MAXIMUM_NUMBER_OF_EPOCHS_FOR_LOCKING) {
                lockInfo.genesisEpoch = m_currentEpoch;
                lockInfo.numberOfEpochsForLocking = MAXIMUM_NUMBER_OF_EPOCHS_FOR_LOCKING;
                emit Extended(tokenId_, numberOfEpochs_, MAXIMUM_NUMBER_OF_EPOCHS_FOR_LOCKING);
            } else {
                lockInfo.numberOfEpochsForLocking += numberOfEpochs_;
                emit Extended(tokenId_, numberOfEpochs_, m_numberOfEpochsForLocking + numberOfEpochs_);
            }
        }
    }

    /// @inheritdoc IVeHZV1
    function merge(uint256 tokenId0_, uint256 tokenId1_) external {
        if (tokenId0_ == tokenId1_) {
            revert TokenIdsCannotBeEqual();
        }
        if (ownerOf(tokenId0_) != msg.sender) {
            revert IncorrectOwner(tokenId0_);
        }
        if (ownerOf(tokenId1_) != msg.sender) {
            revert IncorrectOwner(tokenId1_);
        }
        uint256 numberOfRemainingEpochs0 = numberOfRemainingEpochsByTokenId(tokenId0_);
        uint256 numberOfRemainingEpochs1 = numberOfRemainingEpochsByTokenId(tokenId1_);
        uint256 lockedAmount = lockInfoByTokenId[tokenId0_].lockedAmount + lockInfoByTokenId[tokenId1_].lockedAmount;
        uint256 numberOfEpochsForLocking;
        if (numberOfRemainingEpochs0 > numberOfRemainingEpochs1) {
            numberOfEpochsForLocking = numberOfRemainingEpochs0;
        } else {
            numberOfEpochsForLocking = numberOfRemainingEpochs1;
        }
        uint256 initialPower;
        if (numberOfEpochsForLocking == MAXIMUM_NUMBER_OF_EPOCHS_FOR_LOCKING) {
            initialPower = lockedAmount;
        } else {
            unchecked {
                initialPower = 
                    lockedAmount 
                    * numberOfEpochsForLocking 
                    * POWER_INCREASE_PERCENTAGE 
                    / BASE_PERCENTAGE;
            }
        }
        uint256 tokenId = _tokenId.current();
        lockInfoByTokenId[tokenId] = LockInfo(
            lockedAmount, 
            initialPower,
            numberOfEpochsForLocking, 
            gaugeFactory.currentEpoch()
        );
        _safeMint(msg.sender, tokenId);
        _tokenId.increment();
        delete lockInfoByTokenId[tokenId0_];
        _burn(tokenId0_);
        delete lockInfoByTokenId[tokenId1_];
        _burn(tokenId1_);
        emit Merged(tokenId0_, tokenId1_, tokenId);
    }

    /// @inheritdoc IVeHZV1
    function numberOfHolders() external view returns (uint256) {
        return _holders.length();
    }

    /// @inheritdoc IVeHZV1
    function getHolderAt(uint256 index_) external view returns (address) {
        return _holders.at(index_);
    } 

    /// @inheritdoc IVeHZV1
    function totalPowerByTokenId(uint256 tokenId_) public view returns (uint256 currentPower) {
        if (!_exists(tokenId_)) {
            revert NonExistentToken();
        }
        LockInfo storage lockInfo = lockInfoByTokenId[tokenId_];
        uint256 numberOfPassedEpochs;
        unchecked {
            numberOfPassedEpochs = gaugeFactory.currentEpoch() - lockInfo.genesisEpoch;
        }
        if (numberOfPassedEpochs >= lockInfo.numberOfEpochsForLocking) {
            return 0;
        } else {
            return 
                lockInfo.initialPower 
                - lockInfo.lockedAmount 
                * numberOfPassedEpochs 
                * POWER_INCREASE_PERCENTAGE 
                / BASE_PERCENTAGE;
        }
    }

    /// @inheritdoc IVeHZV1
    function availablePowerByTokenId(uint256 tokenId_) public view returns (uint256) {
        return 
            totalPowerByTokenId(tokenId_) 
            - usedPowerByTokenIdAndEpoch[tokenId_][gaugeFactory.currentEpoch()];
    }

    /// @inheritdoc IVeHZV1
    function numberOfRemainingEpochsByTokenId(uint256 tokenId_) public view returns (uint256) {
        LockInfo storage lockInfo = lockInfoByTokenId[tokenId_];
        uint256 m_numberOfEpochsForLocking = lockInfo.numberOfEpochsForLocking;
        uint256 numberOfPassedEpochs = gaugeFactory.currentEpoch() - lockInfo.genesisEpoch;
        if (numberOfPassedEpochs >= m_numberOfEpochsForLocking) {
            return 0;
        } else {
            unchecked {
                return m_numberOfEpochsForLocking - numberOfPassedEpochs;
            }
        }
    }

    /// @inheritdoc IERC165Upgradeable
    function supportsInterface(
        bytes4 interfaceId_
    )
        public
        view
        override(ERC721EnumerableUpgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId_);
    }

    /// @inheritdoc ERC721Upgradeable
    function _beforeTokenTransfer(
        address from_, 
        address to_, 
        uint256 tokenId_, 
        uint256 batchSize_
    ) 
        internal 
        override 
    {
        if (usedPowerByTokenIdAndEpoch[tokenId_][gaugeFactory.currentEpoch()] != 0) {
            revert ForbiddenToTransferTokensWithUsedPower();
        }
        if (to_ != address(0) && balanceOf(to_) == 0) {
            _holders.add(to_);
        }
        super._beforeTokenTransfer(from_, to_, tokenId_, batchSize_);
    }

    /// @inheritdoc ERC721Upgradeable
    function _afterTokenTransfer(
        address from_, 
        address to_, 
        uint256 tokenId_, 
        uint256 batchSize_
    ) 
        internal 
        override 
    {
        if (from_ != address(0) && balanceOf(from_) == 0) {
            _holders.remove(from_);
        }
        super._afterTokenTransfer(from_, to_, tokenId_, batchSize_);
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}