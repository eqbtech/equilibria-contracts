// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IStandardizedYield {
    /**
     * @notice returns the address of the underlying yield token
     */
    function yieldToken() external view returns (address);

    /**
     * @notice returns all tokens that can mint this SY
     */
    function getTokensIn() external view returns (address[] memory res);
}
