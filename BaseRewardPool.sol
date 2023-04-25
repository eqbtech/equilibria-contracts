// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./Interfaces/IBaseRewardPool.sol";
import "./Interfaces/IPendleBooster.sol";
import "@shared/lib-contracts-v0.8/contracts/Dependencies/TransferHelper.sol";

contract BaseRewardPool is IBaseRewardPool, OwnableUpgradeable {
    using SafeERC20 for IERC20;
    using TransferHelper for address;

    address public operator;
    address public booster;
    uint256 public pid;

    IERC20 public override stakingToken;
    address[] public rewardTokens;

    uint256 public constant duration = 7 days;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    struct Reward {
        uint256 periodFinish;
        uint256 rewardRate;
        uint256 lastUpdateTime;
        uint256 rewardPerTokenStored;
        uint256 queuedRewards;
    }

    struct UserReward {
        uint256 userRewardPerTokenPaid;
        uint256 rewards;
    }

    mapping(address => Reward) public rewards;
    mapping(address => bool) public isRewardToken;

    mapping(address => mapping(address => UserReward)) public userRewards;

    mapping(address => bool) public access;

    mapping(address => bool) public grants;

    mapping(address => uint256) public userLastTime;

    mapping(address => uint256) public userAmountTime;

    function initialize(address _operator) public initializer {
        __Ownable_init();

        operator = _operator;

        emit OperatorUpdated(_operator);
    }

    function setParams(
        address _booster,
        uint256 _pid,
        address _stakingToken,
        address _rewardToken
    ) external override {
        require(msg.sender == owner() || msg.sender == operator, "!auth");

        require(booster == address(0), "params has already been set");
        require(_booster != address(0), "invalid _booster!");
        require(_stakingToken != address(0), "invalid _stakingToken!");
        require(_rewardToken != address(0), "invalid _rewardToken!");

        booster = _booster;

        pid = _pid;
        stakingToken = IERC20(_stakingToken);

        addRewardToken(_rewardToken);

        access[_booster] = true;

        emit BoosterUpdated(_booster);
    }

    function addRewardToken(address _rewardToken) internal {
        require(_rewardToken != address(0), "invalid _rewardToken!");
        if (isRewardToken[_rewardToken]) {
            return;
        }
        rewardTokens.push(_rewardToken);
        isRewardToken[_rewardToken] = true;

        emit RewardTokenAdded(_rewardToken);
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    modifier updateReward(address _account) {
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address rewardToken = rewardTokens[i];
            Reward storage reward = rewards[rewardToken];
            reward.rewardPerTokenStored = rewardPerToken(rewardToken);
            reward.lastUpdateTime = lastTimeRewardApplicable(rewardToken);

            UserReward storage userReward = userRewards[_account][rewardToken];
            userReward.rewards = earned(_account, rewardToken);
            userReward.userRewardPerTokenPaid = rewards[rewardToken]
                .rewardPerTokenStored;
        }

        userAmountTime[_account] = getUserAmountTime(_account);
        userLastTime[_account] = block.timestamp;

        _;
    }

    function getRewardTokens()
        external
        view
        override
        returns (address[] memory)
    {
        return rewardTokens;
    }

    function getRewardTokensLength() external view override returns (uint256) {
        return rewardTokens.length;
    }

    function lastTimeRewardApplicable(
        address _rewardToken
    ) public view returns (uint256) {
        return Math.min(block.timestamp, rewards[_rewardToken].periodFinish);
    }

    function rewardPerToken(
        address _rewardToken
    ) public view returns (uint256) {
        Reward memory reward = rewards[_rewardToken];
        if (totalSupply() == 0) {
            return reward.rewardPerTokenStored;
        }
        return
            reward.rewardPerTokenStored +
            (((lastTimeRewardApplicable(_rewardToken) - reward.lastUpdateTime) *
                reward.rewardRate *
                1e18) / totalSupply());
    }

    function earned(
        address _account,
        address _rewardToken
    ) public view override returns (uint256) {
        UserReward memory userReward = userRewards[_account][_rewardToken];
        return
            ((balanceOf(_account) *
                (rewardPerToken(_rewardToken) -
                    userReward.userRewardPerTokenPaid)) / 1e18) +
            userReward.rewards;
    }

    function getUserAmountTime(
        address _account
    ) public view override returns (uint256) {
        uint256 lastTime = userLastTime[_account];
        if (lastTime == 0) {
            return 0;
        }
        uint256 userBalance = _balances[_account];
        if (userBalance == 0) {
            return userAmountTime[_account];
        }
        return
            userAmountTime[_account] +
            ((block.timestamp - lastTime) * userBalance);
    }

    function stake(uint256 _amount) public override updateReward(msg.sender) {
        require(_amount > 0, "RewardPool : Cannot stake 0");

        _totalSupply = _totalSupply + _amount;
        _balances[msg.sender] = _balances[msg.sender] + _amount;

        stakingToken.safeTransferFrom(msg.sender, address(this), _amount);
        emit Staked(msg.sender, _amount);
    }

    function stakeAll() external override {
        uint256 balance = stakingToken.balanceOf(msg.sender);
        stake(balance);
    }

    function stakeFor(
        address _for,
        uint256 _amount
    ) external override updateReward(_for) {
        require(_for != address(0), "invalid _for!");
        require(_amount > 0, "RewardPool : Cannot stake 0");

        //give to _for
        _totalSupply = _totalSupply + _amount;
        _balances[_for] = _balances[_for] + _amount;

        //take away from sender
        stakingToken.safeTransferFrom(msg.sender, address(this), _amount);
        emit Staked(_for, _amount);
    }

    function withdraw(uint256 amount) external override {
        _withdraw(msg.sender, amount);
    }

    function withdrawAll() external override {
        _withdraw(msg.sender, _balances[msg.sender]);
    }

    function withdrawFor(address _account, uint256 _amount) external override {
        require(grants[msg.sender], "!auth");

        _withdraw(_account, _amount);
    }

    function _withdraw(
        address _account,
        uint256 _amount
    ) internal updateReward(_account) {
        require(_amount > 0, "RewardPool : Cannot withdraw 0");

        _totalSupply = _totalSupply - _amount;
        _balances[_account] = _balances[_account] - _amount;

        stakingToken.safeTransfer(_account, _amount);
        emit Withdrawn(_account, _amount);

        getReward(_account);
    }

    function getReward(
        address _account
    ) public override updateReward(_account) {
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address rewardToken = rewardTokens[i];
            uint256 reward = earned(_account, rewardToken);
            if (reward > 0) {
                userRewards[_account][rewardToken].rewards = 0;
                rewardToken.safeTransferToken(_account, reward);
                IPendleBooster(booster).rewardClaimed(
                    pid,
                    _account,
                    rewardToken,
                    reward
                );
                emit RewardPaid(_account, rewardToken, reward);
            }
        }
    }

    function donate(
        address _rewardToken,
        uint256 _amount
    ) external payable override {
        require(isRewardToken[_rewardToken], "invalid token");
        if (AddressLib.isPlatformToken(_rewardToken)) {
            require(_amount == msg.value, "invalid amount");
        } else {
            require(msg.value == 0, "invalid msg.value");
            IERC20(_rewardToken).safeTransferFrom(
                msg.sender,
                address(this),
                _amount
            );
        }

        rewards[_rewardToken].queuedRewards =
            rewards[_rewardToken].queuedRewards +
            _amount;
    }

    function queueNewRewards(
        address _rewardToken,
        uint256 _rewards
    ) external payable override {
        require(access[msg.sender], "!auth");

        addRewardToken(_rewardToken);

        if (AddressLib.isPlatformToken(_rewardToken)) {
            require(_rewards == msg.value, "invalid amount");
        } else {
            require(msg.value == 0, "invalid msg.value");
            IERC20(_rewardToken).safeTransferFrom(
                msg.sender,
                address(this),
                _rewards
            );
        }

        Reward storage rewardInfo = rewards[_rewardToken];

        if (totalSupply() == 0) {
            rewardInfo.queuedRewards = rewardInfo.queuedRewards + _rewards;
            return;
        }

        rewardInfo.rewardPerTokenStored = rewardPerToken(_rewardToken);

        _rewards = _rewards + rewardInfo.queuedRewards;
        rewardInfo.queuedRewards = 0;

        if (block.timestamp >= rewardInfo.periodFinish) {
            rewardInfo.rewardRate = _rewards / duration;
        } else {
            uint256 remaining = rewardInfo.periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardInfo.rewardRate;
            _rewards = _rewards + leftover;
            rewardInfo.rewardRate = _rewards / duration;
        }
        rewardInfo.lastUpdateTime = block.timestamp;
        rewardInfo.periodFinish = block.timestamp + duration;
        emit RewardAdded(_rewardToken, _rewards);
    }

    function grant(address _address, bool _grant) external onlyOwner {
        require(_address != address(0), "invalid _address!");

        grants[_address] = _grant;
        emit Granted(_address, _grant);
    }

    function setAccess(
        address _address,
        bool _status
    ) external override onlyOwner {
        require(_address != address(0), "invalid _address!");

        access[_address] = _status;
        emit AccessSet(_address, _status);
    }

    receive() external payable {}
}
