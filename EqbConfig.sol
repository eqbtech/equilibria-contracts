// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import "./Interfaces/IEqbConfig.sol";

contract EqbConfig is IEqbConfig, AccessControlUpgradeable {
    mapping(bytes32 => address) public contractMap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function setContract(
        bytes32 _contractKey,
        address _contractAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_contractAddress != address(0), "invalid _contractAddress!");
        require(
            contractMap[_contractKey] != _contractAddress,
            "_contractAddress already set!"
        );

        contractMap[_contractKey] = _contractAddress;
        emit ContractSet(_contractKey, _contractAddress);
    }

    function getContract(
        bytes32 _contractKey
    ) public view override returns (address) {
        return contractMap[_contractKey];
    }
}
