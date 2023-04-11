// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./Interfaces/IBaseRewardPool.sol";
import "./Interfaces/IVlEqb.sol";

contract VlEqb is IVlEqb, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    address public pendle;
    IERC20 public eqb;

    address public booster;
    address public pendleDepositor;
    address public ePendleRewards;
    IERC20 public ePendleToken;

    uint256 public constant WEEK = 86400 * 7;
    uint256 public constant MAX_LOCK_WEEKS = 52;

    struct LockData {
        mapping(uint256 => uint256) weeklyWeight;
        mapping(uint256 => uint256) weeklyUnlock;
        uint256 lastUnlockedWeek;
    }

    // user address => LockData
    mapping(address => LockData) public userLockData;

    mapping(uint256 => uint256) public weeklyTotalWeight;

    // when set to true, other accounts cannot call `lock` on behalf of an account
    mapping(address => bool) public blockThirdPartyActions;

    address[] public rewardTokens;
    mapping(address => bool) public isRewardToken;

    // reward token address => queued rewards
    mapping(address => uint256) public queuedRewards;

    // reward token address => week => rewards
    mapping(address => mapping(uint256 => uint256)) public weeklyRewards;

    // user address => last claimed week
    mapping(address => uint256) public lastClaimedWeek;

    mapping(address => bool) public access;

    event LockCreated(address indexed _user, uint256 _amount, uint256 _weeks);

    event LockExtended(
        address indexed _user,
        uint256 _amount,
        uint256 _oldWeeks,
        uint256 _newWeeks
    );

    event Unlocked(
        address indexed _user,
        uint256 _amount,
        uint256 _lastUnlockedWeek
    );

    event RewardTokenAdded(address indexed _rewardToken);

    event RewardAdded(address indexed _rewardToken, uint256 _reward);

    event RewardPaid(
        address indexed _user,
        address indexed _rewardToken,
        uint256 _reward
    );

    event AccessSet(address indexed _address, bool _status);

    event Migrated(address indexed _user, uint256 _amount, uint256 _weeks);

    function initialize() public initializer {
        __Ownable_init();
    }

    function setParams(
        address _eqb,
        address _pendle,
        address _pendleDepositor,
        address _ePendleRewards,
        address _ePendleToken,
        address _booster
    ) external onlyOwner {
        require(address(eqb) == address(0), "!init");

        require(_eqb != address(0), "invalid _eqb!");
        require(_pendle != address(0), "invalid _pendle!");
        require(_pendleDepositor != address(0), "invalid _pendleDepositor!");
        require(_ePendleRewards != address(0), "invalid _ePendleRewards!");
        require(_ePendleToken != address(0), "invalid _ePendleToken!");
        require(_booster != address(0), "invalid _booster!");

        eqb = IERC20(_eqb);
        pendle = _pendle;

        pendleDepositor = _pendleDepositor;
        ePendleRewards = _ePendleRewards;
        ePendleToken = IERC20(_ePendleToken);

        booster = _booster;
        setAccess(_booster, true);
    }

    function userWeight(address _user) external view returns (uint256) {
        return userLockData[_user].weeklyWeight[_getCurWeek()];
    }

    function userWeightAt(
        address _user,
        uint256 _week
    ) public view returns (uint256) {
        return userLockData[_user].weeklyWeight[_week];
    }

    function userUnlock(address _user) external view returns (uint256) {
        return userLockData[_user].weeklyUnlock[_getCurWeek()];
    }

    function userUnlockAt(
        address _user,
        uint256 _week
    ) external view returns (uint256) {
        return userLockData[_user].weeklyUnlock[_week];
    }

    function totalWeight() public view returns (uint256) {
        return weeklyTotalWeight[_getCurWeek()];
    }

    function totalWeightAt(uint256 _week) public view returns (uint256) {
        return weeklyTotalWeight[_week];
    }

    function getActiveLocks(
        address _user
    ) external view returns (uint256[2][] memory) {
        uint256 nextWeek = _getNextWeek();
        uint256[] memory unlocks = new uint256[](MAX_LOCK_WEEKS + 1);
        uint256 unlockNum = 0;
        for (uint256 i = 0; i <= MAX_LOCK_WEEKS; i++) {
            unlocks[i] = userLockData[_user].weeklyUnlock[
                nextWeek + (i * WEEK)
            ];
            if (unlocks[i] > 0) {
                unlockNum++;
            }
        }
        uint256[2][] memory lockData = new uint256[2][](unlockNum);
        uint256 j = 0;
        for (uint256 i = 0; i <= MAX_LOCK_WEEKS; i++) {
            if (unlocks[i] > 0) {
                lockData[j] = [nextWeek + (i * WEEK), unlocks[i]];
                j++;
            }
        }
        return lockData;
    }

    // Get the amount of eqb in expired locks that is eligible to be released
    function getUnlockable(address _user) public view returns (uint256) {
        uint256 finishedWeek = _getCurWeek();

        LockData storage data = userLockData[_user];

        // return 0 if user has never locked
        if (data.lastUnlockedWeek == 0) {
            return 0;
        }
        uint256 amount;

        for (
            uint256 cur = data.lastUnlockedWeek + WEEK;
            cur <= finishedWeek;
            cur = cur + WEEK
        ) {
            amount = amount + data.weeklyUnlock[cur];
        }
        return amount;
    }

    // Allow or block third-party calls on behalf of the caller
    function setBlockThirdPartyActions(bool _block) external {
        blockThirdPartyActions[msg.sender] = _block;
    }

    function lock(
        address _user,
        uint256 _amount,
        uint256 _weeks
    ) external override {
        require(_user != address(0), "invalid _user!");
        require(
            msg.sender == _user || !blockThirdPartyActions[_user],
            "Cannot lock on behalf of this account"
        );

        require(_weeks > 0, "Min 1 week");
        require(_weeks <= MAX_LOCK_WEEKS, "Exceeds MAX_LOCK_WEEKS");
        require(_amount > 0, "Amount must be nonzero");

        eqb.safeTransferFrom(msg.sender, address(this), _amount);

        uint256 start = _getNextWeek();
        _increaseAmount(_user, start, _amount, _weeks, 0);

        uint256 end = start + (_weeks * WEEK);
        userLockData[_user].weeklyUnlock[end] =
            userLockData[_user].weeklyUnlock[end] +
            _amount;

        uint256 curWeek = _getCurWeek();
        if (userLockData[_user].lastUnlockedWeek == 0) {
            userLockData[_user].lastUnlockedWeek = curWeek;
        }
        if (lastClaimedWeek[_user] == 0) {
            lastClaimedWeek[_user] = curWeek;
        }

        emit LockCreated(_user, _amount, _weeks);
    }

    /**
        @notice Extend the length of an existing lock.
        @param _amount Amount of tokens to extend the lock for. When the value given equals
                       the total size of the existing lock, the entire lock is moved.
                       If the amount is less, then the lock is effectively split into
                       two locks, with a portion of the balance extended to the new length
                       and the remaining balance at the old length.
        @param _weeks The number of weeks for the lock that is being extended.
        @param _newWeeks The number of weeks to extend the lock until.
     */
    function extendLock(
        uint256 _amount,
        uint256 _weeks,
        uint256 _newWeeks
    ) external {
        require(_weeks > 0, "Min 1 week");
        require(_newWeeks <= MAX_LOCK_WEEKS, "Exceeds MAX_LOCK_WEEKS");
        require(_weeks < _newWeeks, "newWeeks must be greater than weeks");
        require(_amount > 0, "Amount must be nonzero");

        LockData storage data = userLockData[msg.sender];
        uint256 start = _getNextWeek();
        uint256 oldEnd = start + (_weeks * WEEK);
        require(_amount <= data.weeklyUnlock[oldEnd], "invalid amount");
        data.weeklyUnlock[oldEnd] = data.weeklyUnlock[oldEnd] - _amount;
        uint256 end = start + (_newWeeks * WEEK);
        data.weeklyUnlock[end] = data.weeklyUnlock[end] + _amount;

        _increaseAmount(msg.sender, start, _amount, _newWeeks, _weeks);
        emit LockExtended(msg.sender, _amount, _weeks, _newWeeks);
    }

    function unlock() external {
        uint256 amount = getUnlockable(msg.sender);
        if (amount != 0) {
            eqb.safeTransfer(msg.sender, amount);
        }

        uint256 lastUnlockedWeek = _getCurWeek();
        userLockData[msg.sender].lastUnlockedWeek = lastUnlockedWeek;

        emit Unlocked(msg.sender, amount, lastUnlockedWeek);
    }

    function _getCurWeek() internal view returns (uint256) {
        return (block.timestamp / WEEK) * WEEK;
    }

    function _getNextWeek() internal view returns (uint256) {
        return _getCurWeek() + WEEK;
    }

    /**
        @dev Increase the amount within a lock weight array over a given time period
     */
    function _increaseAmount(
        address _user,
        uint256 _start,
        uint256 _amount,
        uint256 _rounds,
        uint256 _oldRounds
    ) internal {
        LockData storage data = userLockData[_user];
        for (uint256 i = 0; i < _rounds; i++) {
            uint256 curWeek = _start + (i * WEEK);
            uint256 amount = _amount * (_rounds - i);
            if (i < _oldRounds) {
                amount = amount - (_amount * (_oldRounds - i));
            }
            data.weeklyWeight[curWeek] = data.weeklyWeight[curWeek] + amount;
            weeklyTotalWeight[curWeek] = weeklyTotalWeight[curWeek] + amount;
        }
    }

    function earned(
        address _user,
        address _rewardToken
    ) public view returns (uint256) {
        // return 0 if user has never locked
        if (lastClaimedWeek[_user] == 0) {
            return 0;
        }

        uint256 startWeek = lastClaimedWeek[_user] + WEEK;
        uint256 finishedWeek = _getCurWeek() - WEEK;
        uint256 amount = 0;

        for (uint256 cur = startWeek; cur <= finishedWeek; cur = cur + WEEK) {
            uint256 totalW = totalWeightAt(cur);
            if (totalW == 0) {
                continue;
            }
            amount =
                amount +
                ((weeklyRewards[_rewardToken][cur] * userWeightAt(_user, cur)) /
                    totalW);
        }
        return amount;
    }

    function getRewardTokensLength() external view returns (uint256) {
        return rewardTokens.length;
    }

    function _addRewardToken(address _rewardToken) internal {
        if (isRewardToken[_rewardToken]) {
            return;
        }
        rewardTokens.push(_rewardToken);
        isRewardToken[_rewardToken] = true;

        emit RewardTokenAdded(_rewardToken);
    }

    function _getReward(address _user, bool _stake) internal {
        uint256 userLastClaimedWeek = lastClaimedWeek[_user];
        if (
            userLastClaimedWeek == 0 ||
            userLastClaimedWeek >= _getCurWeek() - WEEK
        ) {
            return;
        }
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address rewardToken = rewardTokens[i];
            uint256 reward = earned(_user, rewardToken);
            if (reward > 0) {
                if (rewardToken == address(ePendleToken)) {
                    if (_stake) {
                        ePendleToken.safeApprove(ePendleRewards, 0);
                        ePendleToken.safeApprove(ePendleRewards, reward);
                        IBaseRewardPool(ePendleRewards).stakeFor(_user, reward);
                    } else {
                        ePendleToken.safeTransfer(_user, reward);
                    }
                } else {
                    // other token
                    IERC20(rewardToken).safeTransfer(_user, reward);
                }

                emit RewardPaid(_user, rewardToken, reward);
            }
        }

        lastClaimedWeek[_user] = _getCurWeek() - WEEK;
    }

    function getReward(bool _stake) external {
        _getReward(msg.sender, _stake);
    }

    function donate(address _rewardToken, uint256 _amount) external {
        require(isRewardToken[_rewardToken], "invalid token");
        IERC20(_rewardToken).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );
        queuedRewards[_rewardToken] = queuedRewards[_rewardToken] + _amount;
    }

    function queueNewRewards(address _rewardToken, uint256 _rewards) external {
        require(access[msg.sender], "!auth");

        _addRewardToken(_rewardToken);

        IERC20(_rewardToken).safeTransferFrom(
            msg.sender,
            address(this),
            _rewards
        );

        if (totalWeight() == 0) {
            queuedRewards[_rewardToken] =
                queuedRewards[_rewardToken] +
                _rewards;
            return;
        }

        _rewards = _rewards + queuedRewards[_rewardToken];
        queuedRewards[_rewardToken] = 0;

        uint256 curWeek = _getCurWeek();
        weeklyRewards[_rewardToken][curWeek] =
            weeklyRewards[_rewardToken][curWeek] +
            _rewards;
        emit RewardAdded(_rewardToken, _rewards);
    }

    function setAccess(address _address, bool _status) public onlyOwner {
        access[_address] = _status;
        emit AccessSet(_address, _status);
    }
}
