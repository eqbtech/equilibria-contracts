// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@shared/lib-contracts-v0.8/contracts/Dependencies/TransferHelper.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../Dependencies/EqbConstants.sol";
import "../Interfaces/IERC20MintBurn.sol";
import "../Interfaces/XEPendle/IXEPendleVester.sol";

contract XEPendleVester is IXEPendleVester, AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    uint256 public constant WEEK = 86400 * 7;
    uint256 public constant MIN_WEEK = 1;
    uint256 public constant MAX_WEEK = 25;
    uint256 public constant AWARD_PERCENT_PER_WEEK = 4;

    address public ePendle;
    address public xePendle;
    uint256 public awardPercentPerWeek;

    // all vesting positions
    VestingPosition[] public vestingPositions;
    // user address => vesting position ids
    mapping(address => uint256[]) public userVestingPositions;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _ePendle, address _xePendle) public initializer {
        __AccessControl_init();

        require(_ePendle != address(0), "Vester: invalid _ePendle");
        require(_xePendle != address(0), "Vester: invalid _xePendle");
        ePendle = _ePendle;
        xePendle = _xePendle;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(EqbConstants.ADMIN_ROLE, msg.sender);
    }

    function adminAddEPendle(uint256 _amount) external onlyRole(EqbConstants.ADMIN_ROLE) {
        require(_amount > 0, "Vester: invalid _amount");
        IERC20(ePendle).safeTransferFrom(msg.sender, address(this), _amount);
        IERC20MintBurn(xePendle).mint(msg.sender, _amount);
        emit EPendleAdded(msg.sender, _amount);
    }

    function vest(uint256 _amount, uint256 _weeks) external override {
        require(_amount > 0, "Vester: invalid _amount");
        require(_weeks >= MIN_WEEK && _weeks <= MAX_WEEK, "Vester: invalid _weeks");

        uint256 vestId = vestingPositions.length;
        vestingPositions.push(VestingPosition({
            user: msg.sender,
            amount: _amount,
            start: block.timestamp,
            durationWeeks: _weeks,
            closed: false
        }));
        userVestingPositions[msg.sender].push(vestId);
        IERC20(xePendle).safeTransferFrom(msg.sender, address(this), _amount);
        emit VestingPositionAdded(msg.sender, _amount, _weeks, block.timestamp, vestId);
    }

    function closeVestingPosition(uint256 _vestId) external {
        require(_vestId < vestingPositions.length, "Vester: invalid _vestId");

        VestingPosition storage vestingPosition = vestingPositions[_vestId];
        require(vestingPosition.user == msg.sender, "Vester: invalid user");
        require(_getTimeWeeksAfter(vestingPosition.start, vestingPosition.durationWeeks) < block.timestamp, "Vester: vesting position not matured");
        require(!vestingPosition.closed, "Vester: vesting position already closed");

        // close the vesting position
        vestingPosition.closed = true;

        uint256 _amount = vestingPosition.amount;
        uint256 _rewardAmount = _amount * AWARD_PERCENT_PER_WEEK * vestingPosition.durationWeeks / 100;
        IERC20MintBurn(xePendle).burn(address(this), _amount);
        IERC20(ePendle).safeTransfer(msg.sender, _rewardAmount);

        emit VestingPositionClosed(msg.sender, _amount, _vestId, _rewardAmount);
    }

    function withdraw(uint256 _amount) external onlyRole(EqbConstants.ADMIN_ROLE) {
        require(_amount > 0, "Vester: invalid _amount");
        require(_amount <= IERC20(ePendle).balanceOf(address(this)), "Vester: amount exceeds balance");
        IERC20(ePendle).safeTransfer(msg.sender, _amount);

        emit Withdrawn(msg.sender, _amount);
    }

    function getVestingPosition(uint256 _vestId) external view returns (VestingPosition memory) {
        return vestingPositions[_vestId];
    }

    function getUserVestingPositions(address _user) external view override returns (uint256[] memory) {
        return userVestingPositions[_user];
    }

    function _getTimeWeeksAfter(uint256 _start, uint256 _weeks) internal pure returns (uint256) {
        return _start + _weeks * WEEK;
    }
}