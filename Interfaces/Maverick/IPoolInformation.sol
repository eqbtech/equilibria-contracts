// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IPool.sol";

interface IPoolInformation {
    struct BinInfo {
        uint128 id;
        uint8 kind;
        int32 lowerTick;
        uint128 reserveA;
        uint128 reserveB;
        uint128 mergeId;
    }

    function calculateSwap(
        IPool pool,
        uint128 amount,
        bool tokenAIn,
        bool exactOutput,
        uint256 sqrtPriceLimit
    ) external returns (uint256 returnAmount);

    function calculateMultihopSwap(
        bytes memory path,
        uint256 amount,
        bool exactOutput
    ) external returns (uint256 returnAmount);

    function getActiveBins(
        IPool pool,
        uint128 startBinIndex,
        uint128 endBinIndex
    ) external view returns (BinInfo[] memory bins);

    function getBinDepth(
        IPool pool,
        uint128 binId
    ) external view returns (uint256 depth);

    function getSqrtPrice(IPool pool) external view returns (uint256 sqrtPrice);

    function getBinsAtTick(
        IPool pool,
        int32 tick
    ) external view returns (IPool.BinState[] memory bins);

    function activeTickLiquidity(
        IPool pool
    )
        external
        view
        returns (
            uint256 sqrtPrice,
            uint256 liquidity,
            uint256 reserveA,
            uint256 reserveB
        );

    function tickLiquidity(
        IPool pool,
        int32 tick
    )
        external
        view
        returns (
            uint256 sqrtPrice,
            uint256 liquidity,
            uint256 reserveA,
            uint256 reserveB
        );
}
