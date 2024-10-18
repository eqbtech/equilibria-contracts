// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ILybraConfigurator {
    function eUSDMiningIncentives() external view returns (address);

    function peUSD() external view returns (address);

    function stableToken() external view returns (address);

    /**
     * @dev Returns the address of the eUSD token.
     * @return The address of the eUSD token.
     */
    function getEUSDAddress() external view returns (address);

    /**
     * @dev Returns the address of the Lybra protocol rewards pool.
     * @return The address of the Lybra protocol rewards pool.
     */
    function getProtocolRewardsPool() external view returns (address);

    function mintVault(address pool) external view returns (bool);

    function getVaultWeight(address pool) external view returns (uint256);
}
