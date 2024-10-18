// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ILybraVault {
    function depositedAsset(address user) external view returns (uint256);

    function getBorrowedOf(address user) external view returns (uint256);

    function getVaultType() external pure returns (uint8);

    function getAsset() external view returns (address);

    /**
     * @notice Allowing direct deposits of ETH, the pool may convert it into the corresponding collateral during the implementation.
     * While depositing, it is possible to simultaneously mint eUSD for oneself.
     * Emits a `DepositEther` event.
     *
     * Requirements:
     * - `mintAmount` Send 0 if doesn't mint eUSD
     * - msg.value Must be higher than 0.
     */
    function depositEtherToMint(uint256 mintAmount) external payable;

    /**
     * @notice Deposit collateral and allow minting eUSD for oneself.
     * Emits a `DepositAsset` event.
     *
     * Requirements:
     * - `assetAmount` Must be higher than 1e18.
     * - `mintAmount` Send 0 if doesn't mint eUSD
     */
    function depositAssetToMint(
        uint256 assetAmount,
        uint256 mintAmount
    ) external;

    /**
     * @notice Withdraw collateral assets to an address
     * Emits a `WithdrawEther` event.
     *
     * Requirements:
     * - `onBehalfOf` cannot be the zero address.
     * - `amount` Must be higher than 0.
     *
     */
    function withdraw(address onBehalfOf, uint256 amount) external;

    /**
     * @notice The mint amount number of eUSD/peUSD is minted to the address
     * Emits a `Mint` event.
     *
     * Requirements:
     * - `onBehalfOf` cannot be the zero address.
     */
    function mint(address onBehalfOf, uint256 amount) external;

    /**
     * @notice Burn the amount of eUSD/peUSD and payback the amount of minted peUSD
     * Emits a `Burn` event.
     * Requirements:
     * - `onBehalfOf` cannot be the zero address.
     * - `amount` Must be higher than 0.
     * @dev Calling the internal`_repay`function.
     */
    function burn(address onBehalfOf, uint256 amount) external;
}
