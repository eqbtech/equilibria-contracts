// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "@shared/lib-contracts-v0.8/contracts/Dependencies/TransferHelper.sol";

import "./Dependencies/Errors.sol";
import "./Interfaces/Lybra/ILybraVault.sol";
import "./Interfaces/ILybraBooster.sol";
import "./Interfaces/ILybraProxy.sol";

contract LybraBooster is ILybraBooster, AccessControlUpgradeable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    ILybraProxy lybraProxy;

    EnumerableSet.AddressSet private vaults;

    // vault => reward tokens
    mapping(address => EnumerableSet.AddressSet) private rewardTokens;
    // vault => totalSupply
    mapping(address => uint256) _totalSupply;
    // vault => user => balance
    mapping(address => mapping(address => uint256)) _balances;

    struct Reward {
        uint256 rewardPerTokenStored;
        uint256 queuedRewards;
    }

    struct UserReward {
        uint256 userRewardPerTokenPaid;
        uint256 rewards;
    }

    // vault => user => Reward
    mapping(address => mapping(address => Reward)) public rewards;

    // vault => user => reward token => UserReward
    mapping(address => mapping(address => mapping(address => UserReward)))
        public userRewards;

    mapping(address => bool) public depositPaused;

    bool public harvestOnOperation;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __AccessControl_init();

        harvestOnOperation = true;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    function setParams(
        address _lybraProxy
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        lybraProxy = ILybraProxy(_lybraProxy);
    }

    function setHarvestOnOperation(
        bool _harvestOnOperation
    ) external onlyRole(ADMIN_ROLE) {
        harvestOnOperation = _harvestOnOperation;
    }

    modifier onlyValidVault(address _vault) {
        require(vaults.contains(_vault), "invalid _vault");

        _;
    }

    modifier updateReward(address _vault, address _user) {
        if (harvestOnOperation) {
            lybraProxy.getEUSDMiningIncentives();
        }

        for (uint256 i = 0; i < rewardTokens[_vault].length(); i++) {
            address rewardToken = rewardTokens[_vault].at(i);
            UserReward storage userReward = userRewards[_vault][_user][
                rewardToken
            ];
            userReward.rewards = earned(_vault, _user, rewardToken);
            userReward.userRewardPerTokenPaid = rewards[_vault][rewardToken]
                .rewardPerTokenStored;
        }

        _;
    }

    function addVault(address _vault) external onlyRole(ADMIN_ROLE) {
        require(lybraProxy.isValidVault(_vault), "invalid _vault");
        require(!vaults.contains(_vault), "already added");

        vaults.add(_vault);

        IERC20(ILybraVault(_vault).getAsset()).safeApprove(
            address(lybraProxy),
            type(uint256).max
        );

        emit VaultAdded(_vault);
    }

    function setDepositPaused(
        address _vault,
        bool _paused
    ) external onlyRole(ADMIN_ROLE) {
        depositPaused[_vault] = _paused;
    }

    function getVaults() external view returns (address[] memory) {
        return vaults.values();
    }

    function getRewardTokens(
        address _vault
    ) external view returns (address[] memory) {
        return rewardTokens[_vault].values();
    }

    function earned(
        address _vault,
        address _user,
        address _rewardToken
    ) public view returns (uint256) {
        Reward memory reward = rewards[_vault][_rewardToken];
        UserReward memory userReward = userRewards[_vault][_user][_rewardToken];
        return
            (balanceOf(_vault, _user) *
                (reward.rewardPerTokenStored -
                    userReward.userRewardPerTokenPaid)) /
            1e18 +
            userReward.rewards;
    }

    function totalSupply(
        address _vault
    ) public view onlyValidVault(_vault) returns (uint256) {
        return _totalSupply[_vault];
    }

    function balanceOf(
        address _vault,
        address _user
    ) public view onlyValidVault(_vault) returns (uint256) {
        return _balances[_vault][_user];
    }

    function deposit(
        address _vault,
        uint256 _amount
    ) external payable onlyValidVault(_vault) updateReward(_vault, msg.sender) {
        require(!depositPaused[_vault], "paused");
        if (_amount < 1 ether) {
            revert Errors.InvalidAmount(_amount);
        }

        uint256 depositedAmount;
        if (msg.value == 0) {
            address collateralAsset = ILybraVault(_vault).getAsset();
            IERC20(collateralAsset).safeTransferFrom(
                msg.sender,
                address(this),
                _amount
            );
            depositedAmount = lybraProxy.depositAssetToVault(
                _vault,
                _amount,
                0
            );
        } else {
            require(msg.value == _amount, "invalid msg.value");
            depositedAmount = lybraProxy.depositEtherToVault{value: msg.value}(
                _vault,
                0
            );
        }

        _totalSupply[_vault] += depositedAmount;
        _balances[_vault][msg.sender] += depositedAmount;

        emit Deposited(msg.sender, _vault, 0, _amount, depositedAmount);
    }

    function withdraw(
        address _vault,
        uint256 _amount
    ) external onlyValidVault(_vault) updateReward(_vault, msg.sender) {
        require(_amount > 0, "cannot withdraw 0");

        _totalSupply[_vault] -= _amount;
        _balances[_vault][msg.sender] -= _amount;

        uint256 withdrawAmount = lybraProxy.withdrawFromVault(
            _vault,
            msg.sender,
            _amount
        );

        emit Withdrawn(msg.sender, _vault, _amount, withdrawAmount);
    }

    function getReward(address[] calldata _vaults) external {
        for (uint256 i = 0; i < _vaults.length; i++) {
            _getReward(_vaults[i], msg.sender);
        }
    }

    function _getReward(
        address _vault,
        address _user
    ) internal updateReward(_vault, _user) {
        for (uint256 i = 0; i < rewardTokens[_vault].length(); i++) {
            address rewardToken = rewardTokens[_vault].at(i);
            UserReward storage userReward = userRewards[_vault][_user][
                rewardToken
            ];
            uint256 reward = userReward.rewards;
            if (reward > 0) {
                userReward.rewards = 0;
                TransferHelper.safeTransferToken(rewardToken, _user, reward);
                emit RewardPaid(_vault, _user, rewardToken, reward);
            }
        }
    }

    function _addRewardToken(address _vault, address _rewardToken) internal {
        require(_rewardToken != address(0), "invalid _rewardToken!");
        bool added = rewardTokens[_vault].add(_rewardToken);
        if (added) {
            emit RewardTokenAdded(_vault, _rewardToken);
        }
    }

    function queueNewRewards(
        address _rewardToken,
        uint256 _rewards
    ) external payable override {
        require(
            msg.sender == address(lybraProxy) ||
                hasRole(ADMIN_ROLE, msg.sender),
            "!auth"
        );

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

        uint256[] memory borrowed = new uint256[](vaults.length());
        for (uint256 i = 0; i < vaults.length(); i++) {
            borrowed[i] = ILybraVault(vaults.at(i)).getBorrowedOf(
                address(lybraProxy)
            );
        }
        uint256[] memory weights = new uint256[](vaults.length());
        for (uint256 i = 0; i < vaults.length(); i++) {
            weights[i] = lybraProxy.getVaultWeight(vaults.at(i));
        }
        uint256[] memory shares = new uint256[](vaults.length());
        uint256 totalShare = 0;
        for (uint256 i = 0; i < vaults.length(); i++) {
            shares[i] = (borrowed[i] * weights[i]) / 1e20;
            totalShare += shares[i];
        }
        for (uint256 i = 0; i < vaults.length(); i++) {
            _queueNewRewards(
                vaults.at(i),
                _rewardToken,
                (_rewards * shares[i]) / totalShare
            );
        }

        emit RewardAdded(_rewardToken, _rewards);
    }

    function _queueNewRewards(
        address _vault,
        address _rewardToken,
        uint256 _rewards
    ) internal {
        _addRewardToken(_vault, _rewardToken);

        Reward storage rewardInfo = rewards[_vault][_rewardToken];

        if (totalSupply(_vault) == 0) {
            rewardInfo.queuedRewards = rewardInfo.queuedRewards + _rewards;
            return;
        }

        _rewards = _rewards + rewardInfo.queuedRewards;
        rewardInfo.queuedRewards = 0;
        rewardInfo.rewardPerTokenStored +=
            (_rewards * 1e18) /
            totalSupply(_vault);

        emit VaultRewardAdded(_vault, _rewardToken, _rewards);
    }

    function _approveTokenIfNeeded(
        address _token,
        address _to,
        uint256 _amount
    ) internal {
        if (IERC20(_token).allowance(address(this), _to) < _amount) {
            IERC20(_token).safeApprove(_to, 0);
            IERC20(_token).safeApprove(_to, type(uint256).max);
        }
    }

    receive() external payable {}
}
