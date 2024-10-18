// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IEPendleVaultSidechain {
    function convert(address _token, uint256 _amount) external;
}
