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

    IPoolInformation public maverickPoolInformation;

    address public pendle;
    address public ePendle;
    IMaverickRouter public router;
    IPool public maverickPendleEpendlePool;
    IPendleDepositor public pendleDepositor;
    uint256 public swapThreshold;
    uint256 public maxSwapAmount;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    uint256 public buyPercent;

    function initialize() public initializer {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function setParams(
        address _pendle,
        address _ePendle,
        address _router,
        address _maverickPoolInformation,
        address _maverickPendleEpendlePool,
        address _pendleDepositor
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(pendle == address(0), "already set!");
        require(_pendle != address(0), "invalid _pendle!");
        require(_ePendle != address(0), "invalid _ePendle!");
        require(_router != address(0), "invalid _router!");
        require(
            _maverickPoolInformation != address(0),
            "invalid _maverickPoolInformation!"
        );
        require(
            _maverickPendleEpendlePool != address(0),
            "invalid _maverickPendleEpendlePool!"
        );
        require(_pendleDepositor != address(0), "invalid _pendleDepositor!");

        pendle = _pendle;
        ePendle = _ePendle;
        router = IMaverickRouter(_router);
        maverickPendleEpendlePool = IPool(_maverickPendleEpendlePool);
        maverickPoolInformation = IPoolInformation(_maverickPoolInformation);
        pendleDepositor = IPendleDepositor(_pendleDepositor);
        IERC20(ePendle).safeApprove(_router, type(uint256).max);
        IERC20(pendle).safeApprove(_router, type(uint256).max);
        IERC20(pendle).safeApprove(_pendleDepositor, type(uint256).max);
        swapThreshold = 105;
        maxSwapAmount = 50000 * 1e18;
    }

    function _depositFor(
        uint256 _amount,
        address _for
    ) internal returns (uint256 obtainedAmount) {
        uint256 fromDexAmount;
        uint256 fromDepositAmount;
        uint256 obtainedFromDexAmount;

        IERC20(pendle).safeTransferFrom(msg.sender, address(this), _amount);
        fromDexAmount = _convertOutFromDexAmount(_amount);
        fromDepositAmount = _amount - fromDexAmount;

        if (fromDexAmount > 0) {
            obtainedFromDexAmount = _swapTokens(
                pendle,
                ePendle,
                fromDexAmount,
                fromDexAmount,
                _for
            );
        }

        if (fromDepositAmount > 0) {
            pendleDepositor.deposit(fromDepositAmount, false);
            IERC20(ePendle).safeTransfer(_for, fromDepositAmount);
        }

        emit EPendleObtained(
            _for,
            _amount,
            obtainedFromDexAmount,
            fromDepositAmount
        );
        return obtainedFromDexAmount + fromDepositAmount;
    }

    function estimateTotalConversion(
        uint256 _amount
    ) external override returns (uint256 amountOut) {
        uint256 amountDexIn = _convertOutFromDexAmount(_amount);
        return _estimateOutEPendleAmount(amountDexIn) + (_amount - amountDexIn);
    }

    function _convertOutFromDexAmount(
        uint256 _amount
    ) internal returns (uint256) {
        // if 1 pendle swap more than 1.05(by default) ePendle in dex
        if (
            _estimateOutEPendleAmount(_amount) > (_amount * swapThreshold) / 100
        ) {
            return Math.min((_amount * buyPercent) / 100, maxSwapAmount);
        }
        // or not swap from dex
        return 0;
    }

    function _estimateOutEPendleAmount(
        uint256 _amountSold
    ) internal returns (uint256) {
        if (_amountSold == 0) {
            return 0;
        }
        return
            maverickPoolInformation.calculateSwap(
                maverickPendleEpendlePool,
                uint128(_amountSold),
                _tokenAIsPendle(),
                false,
                0
            );
    }

    function previewAmountOut(
        address _tokenIn,
        uint256 _amount
    ) external view override returns (uint256) {
        require(_tokenIn == pendle || _tokenIn == ePendle, "invalid _tokenIn!");
        if (_amount == 0) {
            return 0;
        }
        uint256 pendleToEPendlePrice = _getPendleToEPendlePrice();
        if (_tokenIn == pendle) {
            uint256 amountDexIn = 0;
            if ((pendleToEPendlePrice * 100) / 1e18 > swapThreshold) {
                amountDexIn = Math.min(_amount, maxSwapAmount);
            }
            return
                (amountDexIn * pendleToEPendlePrice) /
                1e18 +
                (_amount - amountDexIn);
        } else {
            return (_amount * 1e18) / pendleToEPendlePrice;
        }
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

    function swapEPendleForPendle(
        uint256 _amount,
        uint256 _amountOutMinimum,
        address _receiver
    ) external returns (uint256) {
        IERC20(ePendle).safeTransferFrom(msg.sender, address(this), _amount);
        return
            _swapTokens(ePendle, pendle, _amount, _amountOutMinimum, _receiver);
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

    function changeMaxSwapAmount(
        uint256 _maxSwapAmount
    ) external onlyRole(ADMIN_ROLE) {
        maxSwapAmount = _maxSwapAmount;
        emit MaxSwapAmountChanged(_maxSwapAmount);
    }

    function changeBuyPercent(
        uint256 _buyPercent
    ) external onlyRole(ADMIN_ROLE) {
        require(_buyPercent <= 100, "_buyPercent should be less than 100");
        buyPercent = _buyPercent;
        emit BuyPercentChanged(_buyPercent);
    }

    function changeMaverickPendleEpendlePool(
        address _maverickPendleEpendlePool
    ) external onlyRole(ADMIN_ROLE) {
        require(
            _maverickPendleEpendlePool != address(0),
            "invalid _maverickPendleEpendlePool!"
        );
        maverickPendleEpendlePool = IPool(_maverickPendleEpendlePool);
    }

    function _swapTokens(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        uint256 _amountOutMinimum,
        address _receiver
    ) internal returns (uint256) {
        IMaverickRouter.ExactInputParams memory exactInputParams;
        exactInputParams.path = abi.encodePacked(
            _tokenIn,
            maverickPendleEpendlePool,
            _tokenOut
        );
        exactInputParams.recipient = _receiver;
        exactInputParams.deadline = block.timestamp;
        exactInputParams.amountIn = _amountIn;
        exactInputParams.amountOutMinimum = _amountOutMinimum;

        uint256 amountOut = router.exactInput(exactInputParams);

        emit TokenSwapped(
            _tokenIn,
            _tokenOut,
            _amountIn,
            _amountOutMinimum,
            _receiver,
            amountOut
        );

        return amountOut;
    }

    function _getPendleToEPendlePrice() internal view returns (uint256) {
        uint256 sqrtPrice = maverickPoolInformation.getSqrtPrice(
            maverickPendleEpendlePool
        );
        if (_tokenAIsPendle()) {
            return (1e18 * 1e18 * 1e18) / sqrtPrice / sqrtPrice;
        } else {
            return (sqrtPrice * sqrtPrice) / 1e18;
        }
    }

    function _tokenAIsPendle() internal view returns (bool) {
        return address(maverickPendleEpendlePool.tokenA()) == pendle;
    }
}
