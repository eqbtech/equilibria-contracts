// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface ISmartConvertor {
    function estimateTotalConversion(
        uint256 _amount
    ) external view returns (uint256 amountOut);

    function estimateOutAmount(
        address _tokenIn,
        uint256 _amountSold
    ) external view returns (uint256 amountOut);

    function deposit(uint256 _amount) external returns (uint256 obtainedAmount);

    function depositFor(
        uint256 _amount,
        address _for
    ) external returns (uint256 obtainedAmount);

    function swapEPendleForPendle(
        uint256 _amount,
        uint256 _amountOutMinimum,
        address _receiver
    ) external returns (uint256 pendleReceived);

    event EPendleObtained(
        address indexed _user,
        uint256 _depositedPendle,
        uint256 _obtainedFromDexAmount,
        uint256 _obtainedFromDepositAmount
    );

    event TokenSwapped(
        address indexed _tokenIn,
        address indexed _tokenOut,
        uint256 _amountIn,
        uint256 _amountOutMinimum,
        address indexed _receiver,
        uint256 _amountOut
    );

    event SwapThresholdChanged(uint256 _swapThreshold);

    event MaxSwapAmountChanged(uint256 _maxSwapAmount);

    event MaverickPendleEpendlePoolChanged(address _maverickPendleEpendlePool);
}
