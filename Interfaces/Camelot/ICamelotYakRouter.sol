// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

struct FormattedOffer {
    uint256[] amounts;
    address[] adapters;
    address[] path;
    address[] recipients;
    uint256 gasEstimate;
}

struct Trade {
    uint256 amountIn;
    uint256 amountOut;
    address[] path;
    address[] adapters;
    address[] recipients;
}

interface ICamelotYakRouter {
    function findBestPath(
        uint256 _amountIn,
        address _tokenIn,
        address _tokenOut,
        address[] memory _trustedTokens,
        uint256 _maxSteps
    ) external view returns (FormattedOffer memory);

    function swapNoSplit(
        Trade calldata _trade,
        uint256 _fee,
        address _to
    ) external;
}
