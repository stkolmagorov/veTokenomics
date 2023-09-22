// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

import "./interfaces/IGaugeV1.sol";

contract GaugeV1 is 
    IGaugeV1, 
    Initializable, 
    UUPSUpgradeable, 
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    uint256 public constant EPOCH_DURATION = 7 days;
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");

    // V1
    address public token0;
    address public token1;
    address public horiza;
    address public deShare;
    uint256 public totalStake;
    uint256 public rewardRate;
    uint256 public storedRewardPerToken;
    uint256 public lastUpdateTime;
    uint256 public endOfEpoch;
    uint256 public creationEpoch;
    IVeHZV1 public veHZ;
    IDistributorV1 public distributor;
    IGaugeFactoryV1 public gaugeFactory;

    mapping(address => uint256) public stakeByAccount;
    mapping(address => uint256) public storedRewardByAccount;
    mapping(address => uint256) public rewardPerTokenPaidByAccount;
    mapping(address => uint256) public lastEpochRewardApplicableByAccount;
    mapping(uint256 => uint256) public totalPowerByEpoch;
    mapping(address => mapping(uint256 => uint256)) public providedRewardByTokenAndEpoch;
    mapping(address => mapping(uint256 => uint256)) public powerByAccountAndEpoch;
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) public powerByAccountTokenIdAndEpoch;
    mapping(address => mapping(uint256 => EnumerableSetUpgradeable.UintSet)) private _tokenIdsByAccountAndEpoch;

    /// @inheritdoc IGaugeV1
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
        external 
        initializer 
    {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        __ReentrancyGuard_init();
        token0 = token0_;
        token1 = token1_;
        horiza = horiza_;
        deShare = deShare_;
        creationEpoch = gaugeFactory_.currentEpoch();
        veHZ = veHZ_;
        distributor = distributor_;
        gaugeFactory = gaugeFactory_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(DISTRIBUTOR_ROLE, horiza_);
        _grantRole(DISTRIBUTOR_ROLE, address(distributor_));
    }

    /// @inheritdoc IGaugeV1
    function provideReward(address token_, uint256 reward_) external onlyRole(DISTRIBUTOR_ROLE) {
        address m_horiza = horiza;
        if (token_ == m_horiza) {
            _updateReward(address(0));
            unchecked {
                if (block.timestamp >= endOfEpoch) {
                    rewardRate = reward_ / EPOCH_DURATION;
                } else {
                    uint256 remaining = endOfEpoch - block.timestamp;
                    uint256 leftover = remaining * rewardRate;
                    rewardRate = (reward_ + leftover) / EPOCH_DURATION;
                }
                if (rewardRate > IERC20Upgradeable(m_horiza).balanceOf(address(this)) / EPOCH_DURATION) {
                    revert ProvidedRewardTooHigh();
                }
                lastUpdateTime = block.timestamp;
                endOfEpoch = block.timestamp + EPOCH_DURATION;
            }
        } else if (IDistributorV1(msg.sender).isIncentive(token_) || token_ == token0 || token_ == token1) {
            IERC20Upgradeable(token_).safeTransferFrom(msg.sender, address(this), reward_);
            unchecked {
                providedRewardByTokenAndEpoch[token_][gaugeFactory.currentEpoch() - 1] += reward_;
            }
        } else {
            revert InvalidRewardToken(token_);
        }
        emit RewardProvided(token_, reward_);
    }

    /// @inheritdoc IGaugeV1
    function stake(uint256 amount_) external nonReentrant {
        _updateReward(msg.sender);
        unchecked {
            stakeByAccount[msg.sender] += amount_;
            totalStake += amount_;
        }
        IERC20Upgradeable(deShare).safeTransferFrom(msg.sender, address(this), amount_);
        emit Staked(msg.sender, amount_);
    }

    /// @inheritdoc IGaugeV1
    function vote(uint256[] calldata tokenIds_, uint256[] calldata powers_) external {
        if (tokenIds_.length != powers_.length) {
            revert InvalidArrayLengths();
        }
        veHZ.decreaseVotingPower(msg.sender, tokenIds_, powers_);
        uint256 m_currentEpoch = gaugeFactory.currentEpoch();
        EnumerableSetUpgradeable.UintSet storage s_tokenIdsByAccountAndEpoch 
            = _tokenIdsByAccountAndEpoch[msg.sender][m_currentEpoch];
        uint256 totalPower;
        unchecked {
            for (uint256 i = 0; i < tokenIds_.length; i++) {
                if (!s_tokenIdsByAccountAndEpoch.contains(tokenIds_[i])) {
                    s_tokenIdsByAccountAndEpoch.add(tokenIds_[i]);
                }
                powerByAccountTokenIdAndEpoch[msg.sender][tokenIds_[i]][m_currentEpoch] += powers_[i];
                totalPower += powers_[i];
            }
            powerByAccountAndEpoch[msg.sender][m_currentEpoch] += totalPower;
            totalPowerByEpoch[m_currentEpoch] += totalPower;
        }
        emit Voted(msg.sender, tokenIds_, powers_);
    }

    /// @inheritdoc IGaugeV1
    function exit(bool forVoter_) external {
        if (forVoter_) {
            uint256 m_currentEpoch = gaugeFactory.currentEpoch();
            EnumerableSetUpgradeable.UintSet storage s_tokenIdsByAccountAndEpoch 
                = _tokenIdsByAccountAndEpoch[msg.sender][m_currentEpoch];
            uint256 length = s_tokenIdsByAccountAndEpoch.length();
            uint256[] memory tokenIds = new uint256[](length);
            uint256[] memory powers = new uint256[](length);
            for (uint256 i = 0; i < length; ) {
                uint256 tokenId = s_tokenIdsByAccountAndEpoch.at(i);
                tokenIds[i] = tokenId;
                powers[i] = powerByAccountTokenIdAndEpoch[msg.sender][tokenId][m_currentEpoch];
                unchecked {
                    i++;
                }
            }
            unvote(tokenIds, powers);
        } else {
            unstake(stakeByAccount[msg.sender]);
            claim(false);
        }
    }

    /// @inheritdoc IGaugeV1
    function getTokenIdByAccountAndCurrentEpochAt(
        address account_, 
        uint256 index_
    ) 
        external
        view 
        returns (uint256) 
    {
        return _tokenIdsByAccountAndEpoch[account_][gaugeFactory.currentEpoch()].at(index_);
    }

    /// @inheritdoc IGaugeV1
    function getTokenIdsLengthByAccountAndCurrentEpoch(address account_) external view returns (uint256) {
        return _tokenIdsByAccountAndEpoch[account_][gaugeFactory.currentEpoch()].length();
    }

    /// @inheritdoc IGaugeV1
    function unstake(uint256 amount_) public nonReentrant {
        _updateReward(msg.sender);
        totalStake -= amount_;
        stakeByAccount[msg.sender] -= amount_;
        IERC20Upgradeable(deShare).safeTransfer(msg.sender, amount_);
        emit Unstaked(msg.sender, amount_);
    }

    /// @inheritdoc IGaugeV1
    function unvote(uint256[] memory tokenIds_, uint256[] memory powers_) public {
        if (tokenIds_.length != powers_.length) {
            revert InvalidArrayLengths();
        }
        veHZ.increaseVotingPower(tokenIds_, powers_);
        uint256 m_currentEpoch = gaugeFactory.currentEpoch();
        EnumerableSetUpgradeable.UintSet storage s_tokenIdsByAccountAndEpoch 
            = _tokenIdsByAccountAndEpoch[msg.sender][m_currentEpoch];
        uint256 totalPower;
        for (uint256 i = 0; i < tokenIds_.length; ) {
            if (!s_tokenIdsByAccountAndEpoch.contains(tokenIds_[i])) {
                revert IncorrectOwner(tokenIds_[i]);
            }
            powerByAccountTokenIdAndEpoch[msg.sender][tokenIds_[i]][m_currentEpoch] -= powers_[i];
            if (powerByAccountTokenIdAndEpoch[msg.sender][tokenIds_[i]][m_currentEpoch] == 0) {
                s_tokenIdsByAccountAndEpoch.remove(tokenIds_[i]);
            }
            unchecked {
                totalPower += powers_[i];
                i++;
            }
        }
        powerByAccountAndEpoch[msg.sender][m_currentEpoch] -= totalPower;
        totalPowerByEpoch[m_currentEpoch] -= totalPower;
        emit Unvoted(msg.sender, tokenIds_, powers_);
    }

    /// @inheritdoc IGaugeV1
    function claim(bool forVoter_) public nonReentrant {
        if (forVoter_) {
            uint256 m_currentEpoch = gaugeFactory.currentEpoch();
            uint256 m_lastEpochRewardApplicableByAccount = lastEpochRewardApplicableByAccount[msg.sender];
            uint256 startEpoch;
            if (m_lastEpochRewardApplicableByAccount > creationEpoch) {
                startEpoch = m_lastEpochRewardApplicableByAccount;
            } else {
                startEpoch = creationEpoch;
            }
            uint256 endEpoch = m_currentEpoch;
            IDistributorV1 m_distributor = distributor;
            address m_token0 = token0;
            address m_token1 = token1;
            if (!m_distributor.isIncentive(m_token0)) {
                uint256 reward = earnedByVoter(msg.sender, m_token0, startEpoch, endEpoch);
                if (reward > 0) {
                    IERC20Upgradeable(m_token0).safeTransfer(msg.sender, reward);
                    emit Claimed(msg.sender, m_token0, reward);
                }
            }
            if (!m_distributor.isIncentive(m_token1)) {
                uint256 reward = earnedByVoter(msg.sender, m_token1, startEpoch, endEpoch);
                if (reward > 0) {
                    IERC20Upgradeable(m_token1).safeTransfer(msg.sender, reward);
                    emit Claimed(msg.sender, m_token1, reward);
                }
            }
            uint256 length = m_distributor.getIncentivesLength();
            for (uint256 i = 0; i < length; ) {
                address incentive = m_distributor.getIncentiveAt(i);
                uint256 reward = earnedByVoter(msg.sender, incentive, startEpoch, endEpoch);
                if (reward > 0) {
                    IERC20Upgradeable(incentive).safeTransfer(msg.sender, reward);
                    emit Claimed(msg.sender, incentive, reward);
                }
                unchecked {
                    i++;
                }
            }
            lastEpochRewardApplicableByAccount[msg.sender] = m_currentEpoch;
        } else {
            _updateReward(msg.sender);
            uint256 reward = storedRewardByAccount[msg.sender];
            if (reward > 0) {
                storedRewardByAccount[msg.sender] = 0;
                address m_horiza = horiza;
                IERC20Upgradeable(m_horiza).safeTransfer(msg.sender, reward);
                emit Claimed(msg.sender, m_horiza, reward);
            }
        }
    }

    /// @inheritdoc IGaugeV1
    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < endOfEpoch ? block.timestamp : endOfEpoch;
    }

    /// @inheritdoc IGaugeV1
    function rewardPerToken() public view returns (uint256) {
        uint256 m_totalStake = totalStake;
        if (m_totalStake == 0) {
            return storedRewardPerToken;
        }
        return
            (lastTimeRewardApplicable() - lastUpdateTime)
            * rewardRate 
            * 1e18 
            / m_totalStake 
            + storedRewardPerToken;
    }

    /// @inheritdoc IGaugeV1
    function earnedByStaker(address account_) public view returns (uint256) {
        return
            stakeByAccount[account_]
            * (rewardPerToken() - rewardPerTokenPaidByAccount[account_]) 
            / 1e18 
            + storedRewardByAccount[account_];
    }

    /// @inheritdoc IGaugeV1
    function earnedByVoter(
        address account_, 
        address token_, 
        uint256 startEpoch_,
        uint256 endEpoch_
    )
        public
        view
        returns (uint256 result)
    {
        for (uint256 i = startEpoch_; i < endEpoch_; ) {
            unchecked {
                result += 
                    powerByAccountAndEpoch[account_][i] 
                    * providedRewardByTokenAndEpoch[token_][i] 
                    / totalPowerByEpoch[i];
                i++;
            }
        }
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    /// @notice Updates the earnedByVoter reward by `account_`.
    /// @param account_ Account address.
    function _updateReward(address account_) private {
        storedRewardPerToken = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account_ != address(0)) {
            storedRewardByAccount[account_] = earnedByStaker(account_);
            rewardPerTokenPaidByAccount[account_] = storedRewardPerToken;
        }
    }
}