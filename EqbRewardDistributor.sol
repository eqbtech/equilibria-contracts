// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

contract EqbRewardDistributor is AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    address public eqbToken;
    address public xEqbToken;
    uint256 public totalShare;
    // user => share
    mapping(address => uint256) public shareByUser;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // user => token => amount, rewards claimed
    mapping(address => mapping(address => uint256)) public claimedByUser;
    // token => total rewards
    mapping(address => uint256) public totalRewards;

    event eqbTokenUpdated(address indexed _eqbToken);
    event xEqbTokenUpdated(address indexed _xEqbToken);
    event UserShareUpdated(address indexed _user, uint256 _share);
    event RewardsAdded(address indexed _user, address indexed _token, uint256 _rewards);
    event Claimed(address indexed _user, address indexed _token, uint256 _amount);
    event AdminWithdrawn(address indexed _token, uint256 _amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _eqbToken,
        address _xEqbToken,
        address[] calldata _users,
        uint256[] calldata _shares) public initializer {

        require(_eqbToken != address(0), "invalid _eqbToken");
        require(_xEqbToken != address(0), "invalid _xEqbToken");
        require(_users.length > 0, "invalid _users");
        require(_users.length == _shares.length, "invalid _users or _shares");

        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);

        eqbToken = _eqbToken;
        xEqbToken = _xEqbToken;

        for (uint256 i = 0; i < _users.length; i++) {
            require(_shares[i] > 0, "invalid _shares");
            shareByUser[_users[i]] = _shares[i];
            totalShare += _shares[i];
            emit UserShareUpdated(_users[i], _shares[i]);
        }
        emit eqbTokenUpdated(_eqbToken);
        emit xEqbTokenUpdated(_xEqbToken);
    }

    function addRewards(address _token, uint256 _amount) external onlyRole(ADMIN_ROLE) {
        require(_token == eqbToken || _token == xEqbToken, "token not allowed");
        require(_amount > 0, "invalid _amount");
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        totalRewards[_token] += _amount;
        emit RewardsAdded(msg.sender, _token, _amount);
    }

    function adminWithdraw(address _token) external onlyRole(ADMIN_ROLE) {
        uint256 _balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, _balance);

        emit AdminWithdrawn(_token, _balance);
    }

    function claim() external {
        _claim(eqbToken);
        _claim(xEqbToken);
    }

    function getClaimable(address _user) external view returns (uint256, uint256) {
        return (_calculateRewards(_user, eqbToken), _calculateRewards(_user, xEqbToken));
    }

    function _claim(address _token) internal {
        uint256 _rewards = _calculateRewards(msg.sender, _token);
        if (_rewards == 0) {
            return;
        }
        IERC20(_token).safeTransfer(msg.sender, _rewards);
        claimedByUser[msg.sender][_token] += _rewards;

        emit Claimed(msg.sender, _token, _rewards);
    }

    function _calculateRewards(address _user, address _token) internal view returns (uint256) {
        return totalRewards[_token] * shareByUser[_user] / totalShare - claimedByUser[_user][_token];
    }
}
