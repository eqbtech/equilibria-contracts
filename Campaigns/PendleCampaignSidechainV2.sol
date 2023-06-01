// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

contract PendleCampaignSidechainV2 is AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    address public pendle;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    event Staked(address indexed _user, uint256 _amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _pendle) public initializer {
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);

        pendle = _pendle;
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function stake(uint256 _amount) external {
        require(_amount > 0, "Cannot stake 0");

        _totalSupply = _totalSupply + _amount;
        _balances[msg.sender] = _balances[msg.sender] + _amount;

        IERC20(pendle).safeTransferFrom(msg.sender, address(this), _amount);
        emit Staked(msg.sender, _amount);
    }

    function adminWithdrawPendle() external onlyRole(ADMIN_ROLE) {
        IERC20(pendle).safeTransfer(
            msg.sender,
            IERC20(pendle).balanceOf(address(this))
        );
    }
}
