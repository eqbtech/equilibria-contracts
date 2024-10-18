// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "@shared/lib-contracts-v0.8/contracts/Dependencies/TransferHelper.sol";

import "./Interfaces/IRewards.sol";

contract RewardPoolUpg is IRewards, AccessControlUpgradeable {
    using SafeERC20 for IERC20;
    using TransferHelper for address;
    using EnumerableSet for EnumerableSet.AddressSet;

    IERC20 public stakingToken;
    EnumerableSet.AddressSet private rewardTokens;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    struct Reward {
        uint256 rewardPerTokenStored;
        uint256 queuedRewards;
    }

    struct UserReward {
        uint256 userRewardPerTokenPaid;
        uint256 rewards;
    }

    mapping(address => Reward) public rewards;

    mapping(address => mapping(address => UserReward)) public userRewards;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    event RewardTokenAdded(address indexed _rewardToken);
    event Staked(address indexed _user, uint256 _amount);
    event Withdrawn(address indexed _user, uint256 _amount);
    event RewardPaid(
        address indexed _user,
        address indexed _rewardToken,
        uint256 _reward
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function __RewardPool_init(
        address _stakingToken
    ) internal onlyInitializing {
        __RewardPool_init_unchained(_stakingToken);
    }

    function __RewardPool_init_unchained(
        address _stakingToken
    ) internal onlyInitializing {
        __AccessControl_init();

        stakingToken = IERC20(_stakingToken);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address _user) public view returns (uint256) {
        return _balances[_user];
    }

    modifier updateReward(address _user) {
        _beforeUpdateReward(_user);

        for (uint256 i = 0; i < rewardTokens.length(); i++) {
            address rewardToken = rewardTokens.at(i);
            UserReward storage userReward = userRewards[_user][rewardToken];
            userReward.rewards = earned(_user, rewardToken);
            userReward.userRewardPerTokenPaid = rewards[rewardToken]
                .rewardPerTokenStored;
        }

        _;
    }

    function getRewardTokens() external view returns (address[] memory) {
        return rewardTokens.values();
    }

    function earned(
        address _user,
        address _rewardToken
    ) public view returns (uint256) {
        UserReward memory userReward = userRewards[_user][_rewardToken];
        return
            ((balanceOf(_user) *
                (rewards[_rewardToken].rewardPerTokenStored -
                    userReward.userRewardPerTokenPaid)) / 1e18) +
            userReward.rewards;
    }

    function stake(uint256 _amount) public updateReward(msg.sender) {
        require(_amount > 0, "RewardPool : Cannot stake 0");

        stakingToken.safeTransferFrom(msg.sender, address(this), _amount);

        _totalSupply = _totalSupply + _amount;
        _balances[msg.sender] = _balances[msg.sender] + _amount;

        _stake(msg.sender, _amount);
        emit Staked(msg.sender, _amount);
    }

    function withdraw(uint256 _amount) external updateReward(msg.sender) {
        require(_amount > 0, "RewardPool : Cannot withdraw 0");

        _totalSupply = _totalSupply - _amount;
        _balances[msg.sender] = _balances[msg.sender] - _amount;

        _withdraw(msg.sender, _amount);
        stakingToken.safeTransfer(msg.sender, _amount);
        emit Withdrawn(msg.sender, _amount);

        _getReward(msg.sender);
    }

    function getReward() external updateReward(msg.sender) {
        _getReward(msg.sender);
    }

    function _getReward(address _user) internal {
        for (uint256 i = 0; i < rewardTokens.length(); i++) {
            address rewardToken = rewardTokens.at(i);
            uint256 reward = userRewards[_user][rewardToken].rewards;
            if (reward > 0) {
                userRewards[_user][rewardToken].rewards = 0;
                rewardToken.safeTransferToken(_user, reward);
                emit RewardPaid(_user, rewardToken, reward);
            }
        }
    }

    function queueNewRewards(
        address _rewardToken,
        uint256 _rewards
    ) external payable override onlyRole(ADMIN_ROLE) {
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

        _addRewardToken(_rewardToken);

        Reward storage rewardInfo = rewards[_rewardToken];

        if (totalSupply() == 0) {
            rewardInfo.queuedRewards = rewardInfo.queuedRewards + _rewards;
            return;
        }

        _rewards = _rewards + rewardInfo.queuedRewards;
        rewardInfo.queuedRewards = 0;
        rewardInfo.rewardPerTokenStored += (_rewards * 1e18) / totalSupply();

        emit RewardAdded(_rewardToken, _rewards);
    }

    function _addRewardToken(address _rewardToken) internal {
        require(_rewardToken != address(0), "invalid _rewardToken!");
        bool added = rewardTokens.add(_rewardToken);
        if (added) {
            emit RewardTokenAdded(_rewardToken);
        }
    }

    function _stake(address _user, uint256 _amount) internal virtual {}

    function _withdraw(address _user, uint256 _amount) internal virtual {}

    function _beforeUpdateReward(address _user) internal virtual {}

    receive() external payable {}

    uint256[100] private __gap;
}
