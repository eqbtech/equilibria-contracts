// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "@layerzerolabs/solidity-examples/contracts/token/oft/v2/interfaces/IOFTV2.sol";

import "./Interfaces/IEqbExternalToken.sol";
import "./Interfaces/IEPendleVaultSidechain.sol";

contract EPendleVaultSidechain is
    IEPendleVaultSidechain,
    AccessControlUpgradeable
{
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    IEqbExternalToken public ePendle;
    address public swapToken;

    EnumerableSet.AddressSet private convertibleTokens;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    event Converted(address indexed _user, address _token, uint256 _amount);

    event Swapped(address indexed _user, uint256 _amount, address indexed _to);

    event Sent(
        address indexed _user,
        uint16 _dstChainId,
        bytes32 _to,
        uint256 _amount
    );

    event AdminWithdrawn(address indexed _admin, uint256 _amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    function setParams(
        address _ePendle,
        address _swapToken
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_ePendle != address(0), "invalid _ePendle!");
        require(_swapToken != address(0), "invalid _swapToken!");

        ePendle = IEqbExternalToken(_ePendle);
        swapToken = _swapToken;
    }

    modifier onlyConvertibleToken(address _token) {
        require(convertibleTokens.contains(_token), "token not convertible!");

        _;
    }

    function addConvertibleToken(address _token) external onlyRole(ADMIN_ROLE) {
        require(_token != address(0), "invalid _token!");
        require(!convertibleTokens.contains(_token), "already added!");

        convertibleTokens.add(_token);
    }

    function removeConvertibleToken(
        address _token
    ) external onlyRole(ADMIN_ROLE) {
        require(_token != address(0), "invalid _token!");
        require(convertibleTokens.contains(_token), "token not convertible!");

        convertibleTokens.remove(_token);
    }

    function getConvertibleTokens() external view returns (address[] memory) {
        return convertibleTokens.values();
    }

    function convert(
        address _token,
        uint256 _amount
    ) external override onlyConvertibleToken(_token) {
        require(_amount > 0, "invalid _amount!");

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        ePendle.mint(msg.sender, _amount);

        emit Converted(_token, msg.sender, _amount);
    }

    function swap(uint256 _amount, address _to) public {
        require(_amount > 0, "invalid _amount!");
        require(
            IERC20(swapToken).balanceOf(address(this)) >= _amount,
            "not enough token!"
        );

        ePendle.burn(msg.sender, _amount);
        IERC20(swapToken).safeTransfer(_to, _amount);

        emit Swapped(msg.sender, _amount, _to);
    }

    function swapAndSend(
        uint16 _dstChainId,
        bytes32 _to,
        uint256 _amount,
        ICommonOFT.LzCallParams calldata _callParams
    ) external payable {
        swap(_amount, address(this));
        IOFTV2(swapToken).sendFrom{value: msg.value}(
            address(this),
            _dstChainId,
            _to,
            _amount,
            _callParams
        );

        emit Sent(msg.sender, _dstChainId, _to, _amount);
    }

    function adminWithdraw(
        address _token
    ) external onlyRole(ADMIN_ROLE) onlyConvertibleToken(_token) {
        uint256 tokenBal = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, tokenBal);

        emit AdminWithdrawn(msg.sender, tokenBal);
    }
}
