// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface IVaultDepositToken {
    function initialize(
        address _owner,
        address _pendle,
        address _swapRouter,
        address _weth,
        address _usdc,
        bytes memory _pendleToWethPath,
        bytes memory _wethToUsdcPath,
        address _eqbConfig,
        address _booster,
        uint256 _pid
    ) external;

    function pid() external returns (uint256);

    function deposit(uint _amount) external returns (uint256);

    function withdraw(uint256 _shares) external returns (uint256);
}
