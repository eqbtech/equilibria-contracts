// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "./Dependencies/EqbConstants.sol";

import "./Interfaces/IDepositTokenV2.sol";

contract DepositTokenV2 is
    IDepositTokenV2,
    ERC20Upgradeable,
    AccessControlUpgradeable
{
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _owner,
        address _operator,
        address _lptoken
    ) public initializer {
        require(_operator != address(0), "invalid _operator!");

        __AccessControl_init();

        __ERC20_init_unchained(
            string(
                abi.encodePacked(ERC20(_lptoken).name(), " Equilibria Deposit")
            ),
            string(abi.encodePacked("eqb", ERC20(_lptoken).symbol()))
        );

        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(EqbConstants.MINTER_ROLE, _operator);
        _grantRole(EqbConstants.BURNER_ROLE, _operator);
    }

    function mint(
        address _to,
        uint256 _amount
    ) external override onlyRole(EqbConstants.MINTER_ROLE) {
        _mint(_to, _amount);
    }

    function burn(
        address _from,
        uint256 _amount
    ) external override onlyRole(EqbConstants.BURNER_ROLE) {
        _burn(_from, _amount);
    }
}
