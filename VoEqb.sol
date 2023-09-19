// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract VoEqb is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    IERC20 public eqb;

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

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _eqb) public initializer {
        require(_eqb != address(0), "invalid _eqb!");
        __Ownable_init();

        __ReentrancyGuard_init_unchained();

        eqb = IERC20(_eqb);
    }

    function name() external pure returns (string memory) {
        return "vote-only EQB";
    }

    function symbol() external pure returns (string memory) {
        return "voEQB";
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function totalSupply() public view returns (uint256) {
        return totalWeight();
    }

    function balanceOf(address _user) public view returns (uint256) {
        return userWeight(_user);
    }

    function userWeight(address _user) public view returns (uint256) {
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
    ) external nonReentrant {
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
    ) external nonReentrant {
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

    function unlock() external nonReentrant {
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
}
