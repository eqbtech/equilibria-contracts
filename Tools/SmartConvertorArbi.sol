// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import "../Interfaces/IEqbConfig.sol";
import "../Interfaces/ISmartConvertorArbi.sol";
import "../Interfaces/IEPendleVaultSidechain.sol";
import "../Interfaces/Camelot/ICamelotRouter.sol";
import "../Interfaces/Camelot/ICamelotYakRouter.sol";

import "../Dependencies/EqbConstants.sol";

contract SmartConvertorArbi is ISmartConvertorArbi, AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    IEqbConfig public eqbConfig;
    address public pendle;
    address public ePendle;
    address public ePendleVaultSidechain;

    ICamelotYakRouter public camelotYakRouter;
    address[] public trustedTokens;
    uint256 public maxSteps;

    uint256 public swapThreshold;
    uint256 public buyPercent;

    address public camelotRouter;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _eqbConfig,
        address _pendle,
        address _ePendle,
        address _camelotYakRouter,
        address[] memory _trustedTokens,
        uint256 _maxSteps
    ) public initializer {
        __AccessControl_init();

        require(_eqbConfig != address(0), "invalid _eqbConfig!");
        require(_pendle != address(0), "invalid _pendle!");
        require(_ePendle != address(0), "invalid _ePendle!");
        require(_camelotYakRouter != address(0), "invalid _camelotYakRouter!");

        eqbConfig = IEqbConfig(_eqbConfig);
        pendle = _pendle;
        ePendle = _ePendle;
        ePendleVaultSidechain = eqbConfig.getContract(
            EqbConstants.EPENDLE_VAULT_SIDECHAIN
        );

        camelotYakRouter = ICamelotYakRouter(_camelotYakRouter);
        trustedTokens = _trustedTokens;
        maxSteps = _maxSteps;

        swapThreshold = 125;
        buyPercent = 50;

        IERC20(pendle).safeApprove(ePendleVaultSidechain, type(uint256).max);
        IERC20(pendle).safeApprove(_camelotYakRouter, type(uint256).max);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(EqbConstants.ADMIN_ROLE, msg.sender);
    }

    function changeSwapThreshold(
        uint256 _swapThreshold
    ) external onlyRole(EqbConstants.ADMIN_ROLE) {
        require(
            _swapThreshold >= 100,
            "_swapThreshold should be greater than 100"
        );
        swapThreshold = _swapThreshold;
        emit SwapThresholdChanged(_swapThreshold);
    }

    function changeBuyPercent(
        uint256 _buyPercent
    ) external onlyRole(EqbConstants.ADMIN_ROLE) {
        require(_buyPercent <= 100, "_buyPercent should be less than 100");
        buyPercent = _buyPercent;
        emit BuyPercentChanged(_buyPercent);
    }

    function setCamelotRouter(
        address _camelotRouter
    ) external onlyRole(EqbConstants.ADMIN_ROLE) {
        camelotRouter = _camelotRouter;
    }

    function estimateTotalConversion(
        uint256 _amount
    ) external view override returns (uint256) {
        uint256 dexAmount = _getDexAmount(_amount);
        return _getEPendleOutAmount(dexAmount) + (_amount - dexAmount);
    }

    function deposit(uint256 _amount) external override returns (uint256) {
        IERC20(pendle).safeTransferFrom(msg.sender, address(this), _amount);

        uint256 dexAmount = _getDexAmount(_amount);

        uint256 dexAmountOut;
        if (dexAmount > 0) {
            dexAmountOut = _swap(dexAmount);
        }

        uint256 convertAmount = _amount - dexAmount;
        if (convertAmount > 0) {
            IEPendleVaultSidechain(ePendleVaultSidechain).convert(
                pendle,
                convertAmount
            );
        }

        uint256 ePendleAmount = dexAmountOut + convertAmount;
        IERC20(ePendle).safeTransfer(msg.sender, ePendleAmount);

        emit Deposited(msg.sender, _amount, ePendleAmount);
        return ePendleAmount;
    }

    function _getDexAmount(uint256 _amount) internal view returns (uint256) {
        uint256 dexAmount = (_amount * buyPercent) / 100;
        if (
            _getEPendleOutAmount(dexAmount) > (dexAmount * swapThreshold) / 100
        ) {
            return dexAmount;
        }
        return 0;
    }

    function _getEPendleOutAmount(
        uint256 _amountIn
    ) internal view returns (uint256) {
        if (_amountIn == 0) {
            return 0;
        }

        if (camelotRouter != address(0)) {
            address[] memory path = new address[](2);
            path[0] = pendle;
            path[1] = ePendle;
            uint256[] memory amounts = ICamelotRouter(camelotRouter)
                .getAmountsOut(_amountIn, path);
            return amounts[amounts.length - 1];
        }

        FormattedOffer memory offer = camelotYakRouter.findBestPath(
            _amountIn,
            pendle,
            ePendle,
            trustedTokens,
            maxSteps
        );
        return offer.amounts[offer.amounts.length - 1];
    }

    function _swap(uint256 _amountIn) internal returns (uint256) {
        if (_amountIn == 0) {
            return 0;
        }

        uint256 ePendleBalBefore = IERC20(ePendle).balanceOf(address(this));

        if (camelotRouter != address(0)) {
            IERC20(pendle).safeIncreaseAllowance(camelotRouter, _amountIn);
            address[] memory path = new address[](2);
            path[0] = pendle;
            path[1] = ePendle;
            ICamelotRouter(camelotRouter)
                .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                    _amountIn,
                    0,
                    path,
                    address(this),
                    address(0),
                    block.timestamp
                );
        } else {
            FormattedOffer memory offer = camelotYakRouter.findBestPath(
                _amountIn,
                pendle,
                ePendle,
                trustedTokens,
                maxSteps
            );
            camelotYakRouter.swapNoSplit(
                Trade({
                    amountIn: _amountIn,
                    amountOut: offer.amounts[offer.amounts.length - 1],
                    path: offer.path,
                    adapters: offer.adapters,
                    recipients: offer.recipients
                }),
                0,
                address(this)
            );
        }
        uint256 amountOut = IERC20(ePendle).balanceOf(address(this)) -
            ePendleBalBefore;

        emit Swapped(_amountIn, amountOut);

        return amountOut;
    }
}
