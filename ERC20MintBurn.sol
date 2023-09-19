// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "./Interfaces/IERC20MintBurn.sol";

contract ERC20MintBurn is
    IERC20MintBurn,
    ERC20Upgradeable,
    AccessControlUpgradeable
{
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory _name,
        string memory _symbol
    ) public initializer {
        __ERC20_init(_name, _symbol);

        __AccessControl_init_unchained();

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function mint(
        address _to,
        uint256 _amount
    ) external override onlyRole(ADMIN_ROLE) {
        _mint(_to, _amount);
    }

    function burn(
        address _from,
        uint256 _amount
    ) external override onlyRole((ADMIN_ROLE)) {
        _burn(_from, _amount);
    }
}
