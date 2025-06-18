// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface IVaultDepositTokenFactory {
    function isValidVaultDepositToken(
        address _vaultDepositToken
    ) external view returns (bool);
}
