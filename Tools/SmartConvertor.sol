// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "../Interfaces/ISmartConvertor.sol";
import "../Interfaces/Maverick/IMaverickRouter.sol";
import "../Interfaces/Maverick/IPoolInformation.sol";
import "../Interfaces/Maverick/IPool.sol";
import "../Interfaces/IPendleDepositor.sol";

contract SmartConvertor is ISmartConvertor, AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    IPoolInformation poolInformation;

    IERC20 public pendle;
    IERC20 public ePendle;
    IMaverickRouter public router;
    IPool public swapPool;
    IPendleDepositor public pendleDepositor;
    uint256 public swapThreshold;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    event EPendleObtained(
        address _user,
        uint256 _depositedPendle,
        uint256 _obtainedFromDexAmount,
        uint256 _obtainedFromDepositAmount
    );

    event SwapThresholdChanged(uint256 _swapThreshold);

    function initialize() public initializer {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function setParams(
        address _pendle,
        address _ePendle,
        address _router,
        address _poolInformation,
        address _swapPool,
        address _pendleDepositor
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_pendle != address(0), "invalid _pendle!");
        require(_ePendle != address(0), "invalid _ePendle!");
        require(_router != address(0), "invalid _router!");
        require(_poolInformation != address(0), "invalid _poolInformation!");
        require(_swapPool != address(0), "invalid _swapPool!");
        require(_pendleDepositor != address(0), "invalid _pendleDepositor!");

        pendle = IERC20(_pendle);
        ePendle = IERC20(_ePendle);
        router = IMaverickRouter(_router);
        swapPool = IPool(_swapPool);
        poolInformation = IPoolInformation(_poolInformation);
        pendleDepositor = IPendleDepositor(_pendleDepositor);
        pendle.safeApprove(_router, type(uint256).max);
        pendle.safeApprove(_pendleDepositor, type(uint256).max);
        swapThreshold = 105;
    }

    function _depositFor(
        uint256 _amount,
        address _for
    ) internal returns (uint256 obtainedAmount) {
        uint256 fromDexAmount;
        uint256 fromDepositAmount;
        uint256 obtainedFromDexAmount;

        pendle.safeTransferFrom(msg.sender, address(this), _amount);

        //if 1 pendle swap more than 1.05(by default) ePendle in dex
        if (_estimateOutAmount(_amount) > (_amount * swapThreshold) / 100) {
            fromDexAmount = Math.min(_amount, maxAmountToBuy());
        }

        fromDepositAmount = _amount - fromDexAmount;

        if (fromDexAmount > 0) {
            IMaverickRouter.ExactInputParams memory exactInputParams;
            exactInputParams.path = abi.encodePacked(
                address(pendle),
                address(swapPool),
                address(ePendle)
            );
            exactInputParams.recipient = _for;
            exactInputParams.deadline = block.timestamp;
            exactInputParams.amountIn = fromDexAmount;
            exactInputParams.amountOutMinimum = _estimateOutAmount(
                fromDexAmount
            );
            obtainedFromDexAmount = router.exactInput(exactInputParams);
        }

        if (fromDepositAmount > 0) {
            pendleDepositor.deposit(fromDepositAmount, false);
            ePendle.safeTransfer(_for, fromDepositAmount);
        }

        emit EPendleObtained(
            _for,
            _amount,
            obtainedFromDexAmount,
            fromDepositAmount
        );
        return obtainedFromDexAmount + fromDepositAmount;
    }

    function _estimateOutAmount(
        uint256 amountSold
    ) internal returns (uint256 amountOut) {
        return
            poolInformation.calculateSwap(
                swapPool,
                uint128(amountSold),
                _tokenAIsPendle(),
                false,
                0
            );
    }

    function maxAmountToBuy() public view returns (uint256 amountOut) {
        IPoolInformation.BinInfo[] memory bins = poolInformation.getActiveBins(
            swapPool,
            0,
            0
        );
        //step 1: find active bin
        uint256 activeBinIndex = type(uint256).max;
        for (uint256 i = 0; i < bins.length; i++) {
            IPoolInformation.BinInfo memory binInfo = bins[i];
            if ((binInfo.reserveA > 0 && binInfo.reserveB > 0)) {
                activeBinIndex = i;
                break;
            }
        }

        if (activeBinIndex == type(uint256).max) {
            return 0;
        }

        //step 2: sum all ePendle reserve amount
        uint256 sumEPendleReserve = 0;

        if (_tokenAIsPendle()) {
            for (uint256 i = activeBinIndex; i < bins.length; i++) {
                IPoolInformation.BinInfo memory binInfo = bins[i];
                (uint256 sqrtPrice, , , uint256 reserveB) = poolInformation
                    .tickLiquidity(swapPool, binInfo.lowerTick);

                if (sqrtPrice <= 1 * 1e18) {
                    sumEPendleReserve += reserveB;
                } else {
                    break;
                }
            }
        } else {
            for (uint256 i = activeBinIndex; i >= 0; i--) {
                IPoolInformation.BinInfo memory binInfo = bins[i];
                (uint256 sqrtPrice, , uint256 reserveA, ) = poolInformation
                    .tickLiquidity(swapPool, binInfo.lowerTick);

                if (sqrtPrice >= 1 * 1e18) {
                    sumEPendleReserve += reserveA;
                } else {
                    break;
                }
            }
        }

        return sumEPendleReserve;
    }

    function deposit(
        uint256 _amount
    ) external override returns (uint256 obtainedAmount) {
        return _depositFor(_amount, msg.sender);
    }

    function depositFor(
        uint256 _amount,
        address _for
    ) external override returns (uint256 obtainedAmount) {
        return _depositFor(_amount, _for);
    }

    function changeSwapThreshold(
        uint256 _swapThreshold
    ) external onlyRole(ADMIN_ROLE) {
        require(
            _swapThreshold >= 100,
            "_swapThreshold should be greater than 100"
        );
        swapThreshold = _swapThreshold;
        emit SwapThresholdChanged(_swapThreshold);
    }

    function _tokenAIsPendle() internal view returns (bool) {
        return (address(swapPool.tokenA()) == address(pendle));
    }
}
