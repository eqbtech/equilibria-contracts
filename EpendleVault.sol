// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import "./Interfaces/IERC20MintBurn.sol";

contract EpendleVault is AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    address public pendle;

    address public ePendle;

    IERC20MintBurn public ePendleCertificate;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    event Converted(
        address _user,
        uint256 _amount,
        uint256 _ePendleAmount,
        uint256 _ePendleCertificateAmount
    );

    event Redeemed(address _user, uint256 _amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _pendle,
        address _ePendle,
        address _ePendleCertificate
    ) public initializer {
        require(_pendle != address(0), "invalid _pendle!");
        require(_ePendle != address(0), "invalid _ePendle!");
        require(
            _ePendleCertificate != address(0),
            "invalid _ePendleCertificate!"
        );

        __AccessControl_init();

        pendle = _pendle;
        ePendle = _ePendle;
        ePendleCertificate = IERC20MintBurn(_ePendleCertificate);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function convert(uint256 _amount) external {
        require(_amount > 0, "invalid _amount!");

        IERC20(pendle).safeTransferFrom(msg.sender, address(this), _amount);

        uint256 ePendleAmount = Math.min(
            _amount,
            IERC20(ePendle).balanceOf(address(this))
        );

        if (ePendleAmount > 0) {
            IERC20(ePendle).safeTransfer(msg.sender, ePendleAmount);
        }
        if (_amount > ePendleAmount) {
            ePendleCertificate.mint(msg.sender, _amount - ePendleAmount);
        }

        emit Converted(
            msg.sender,
            _amount,
            ePendleAmount,
            _amount - ePendleAmount
        );
    }

    function redeem(uint256 _amount) external {
        require(_amount > 0, "invalid _amount!");
        require(
            IERC20(ePendle).balanceOf(address(this)) >= _amount,
            "not enough ePendle!"
        );

        ePendleCertificate.burn(msg.sender, _amount);

        IERC20(ePendle).safeTransfer(msg.sender, _amount);

        emit Redeemed(msg.sender, _amount);
    }

    function adminWithdrawPendle() external onlyRole(ADMIN_ROLE) {
        IERC20(pendle).safeTransfer(
            msg.sender,
            IERC20(pendle).balanceOf(address(this))
        );
    }
}
