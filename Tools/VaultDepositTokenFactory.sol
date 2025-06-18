// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import "../Dependencies/EqbConstants.sol";
import "../Interfaces/IEqbConfig.sol";
import "../Interfaces/IVaultDepositToken.sol";
import "../Interfaces/IVaultDepositTokenFactory.sol";

contract VaultDepositTokenFactory is
    IVaultDepositTokenFactory,
    AccessControlUpgradeable
{
    using EnumerableSet for EnumerableSet.AddressSet;

    address public pendle;
    address public swapRouter;
    address public weth;
    address public usdc;
    bytes public pendleToWethPath;
    bytes public wethToUsdcPath;
    address public eqbConfig;
    address public booster;
    EnumerableSet.AddressSet private vaultDepositTokens;

    event VaultDepositTokenCreated(address indexed _vaultDepositToken);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _pendle,
        address _swapRouter,
        address _weth,
        address _usdc,
        bytes memory _pendleToWethPath,
        bytes memory _wethToUsdcPath,
        address _eqbConfig,
        address _booster
    ) public initializer {
        pendle = _pendle;
        swapRouter = _swapRouter;
        weth = _weth;
        usdc = _usdc;
        pendleToWethPath = _pendleToWethPath;
        wethToUsdcPath = _wethToUsdcPath;
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
                msg.sender,
                pendle,
                swapRouter,
                weth,
                usdc,
                pendleToWethPath,
                wethToUsdcPath,
                eqbConfig,
                booster,
                _pid
            )
        );

        vaultDepositTokens.add(address(vaultDepositToken));

        emit VaultDepositTokenCreated(address(vaultDepositToken));

        return address(vaultDepositToken);
    }

    function isValidVaultDepositToken(
        address _vaultDepositToken
    ) external view override returns (bool) {
        return vaultDepositTokens.contains(_vaultDepositToken);
    }
}
