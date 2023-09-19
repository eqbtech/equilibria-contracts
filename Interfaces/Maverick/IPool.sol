// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IPool {
    struct BinDelta {
        uint128 deltaA;
        uint128 deltaB;
        uint256 deltaLpBalance;
        uint128 binId;
        uint8 kind;
        int32 lowerTick;
        bool isActive;
    }

    struct TwaState {
        int96 twa;
        int96 value;
        uint64 lastTimestamp;
    }

    struct BinState {
        uint128 reserveA;
        uint128 reserveB;
        uint128 mergeBinBalance;
        uint128 mergeId;
        uint128 totalSupply;
        uint8 kind;
        int32 lowerTick;
    }

    struct AddLiquidityParams {
        uint8 kind;
        int32 pos;
        bool isDelta;
        uint128 deltaA;
        uint128 deltaB;
    }

    struct RemoveLiquidityParams {
        uint128 binId;
        uint128 amount;
    }

    struct State {
        int32 activeTick;
        uint8 status;
        uint128 binCounter;
        uint64 protocolFeeRatio;
    }

    function fee() external view returns (uint256);

    function tickSpacing() external view returns (uint256);

    function tokenA() external view returns (IERC20);

    function tokenB() external view returns (IERC20);

    function binMap(int32 tick) external view returns (uint256);

    function binPositions(
        int32 tick,
        uint256 kind
    ) external view returns (uint128);

    function binBalanceA() external view returns (uint128);

    function binBalanceB() external view returns (uint128);

    function getTwa() external view returns (TwaState memory);

    function getCurrentTwa() external view returns (int256);

    function getState() external view returns (State memory);

    function addLiquidity(
        uint256 tokenId,
        AddLiquidityParams[] calldata params,
        bytes calldata data
    )
        external
        returns (
            uint256 tokenAAmount,
            uint256 tokenBAmount,
            BinDelta[] memory binDeltas
        );

    function transferLiquidity(
        uint256 fromTokenId,
        uint256 toTokenId,
        RemoveLiquidityParams[] calldata params
    ) external;

    function removeLiquidity(
        address recipient,
        uint256 tokenId,
        RemoveLiquidityParams[] calldata params
    )
        external
        returns (
            uint256 tokenAOut,
            uint256 tokenBOut,
            BinDelta[] memory binDeltas
        );

    function migrateBinUpStack(uint128 binId, uint32 maxRecursion) external;

    function swap(
        address recipient,
        uint256 amount,
        bool tokenAIn,
        bool exactOutput,
        uint256 sqrtPriceLimit,
        bytes calldata data
    ) external returns (uint256 amountIn, uint256 amountOut);

    function getBin(uint128 binId) external view returns (BinState memory bin);

    function balanceOf(
        uint256 tokenId,
        uint128 binId
    ) external view returns (uint256 lpToken);

    function tokenAScale() external view returns (uint256);

    function tokenBScale() external view returns (uint256);
}
