// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./IBalancerVault.sol";

interface IBalancerQueries {
    function querySwap(
        IBalancerVault.SingleSwap memory singleSwap,
        IBalancerVault.FundManagement memory funds
    ) external view returns (uint256);
}
