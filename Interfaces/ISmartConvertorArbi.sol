// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ISmartConvertorArbi {
    function estimateTotalConversion(
        uint256 _amount
    ) external view returns (uint256);

    function deposit(uint256 _amount) external returns (uint256);

    event Deposited(
        address indexed _user,
        uint256 _pendleAmount,
        uint256 _ePendleAmount
    );

    event Swapped(uint256 _amountIn, uint256 _amountOut);

    event SwapThresholdChanged(uint256 _swapThreshold);

    event BuyPercentChanged(uint256 _buyPercent);
}
