// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import "../Dependencies/EqbConstants.sol";
import "../Interfaces/IEqbConfig.sol";
import "../Interfaces/IVaultDepositToken.sol";

contract VaultDepositTokenFactory is AccessControlUpgradeable {
    address public pendle;
    address public eqbConfig;
    address public booster;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _pendle,
        address _eqbConfig,
        address _booster
    ) public initializer {
        pendle = _pendle;
        eqbConfig = _eqbConfig;
        booster = _booster;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(EqbConstants.ADMIN_ROLE, msg.sender);
    }

    function createVault(
        uint256 _pid
    ) external onlyRole(EqbConstants.ADMIN_ROLE) returns (address) {
        BeaconProxy vaultDepositToken = new BeaconProxy(
            IEqbConfig(eqbConfig).getContract(
                EqbConstants.VAULT_DEPOSIT_TOKEN_BEACON
            ),
            abi.encodeWithSelector(
                IVaultDepositToken.initialize.selector,
                pendle,
                eqbConfig,
                booster,
                _pid
            )
        );

        return address(vaultDepositToken);
    }
}
