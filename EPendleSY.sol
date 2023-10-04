// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@pendle/core-v2/contracts/core/StandardizedYield/SYBaseWithRewards.sol";
import "./Interfaces/ISmartConvertor.sol";
import "./Interfaces/IBaseRewardPool.sol";
import "./Interfaces/Balancer/IBalancerVault.sol";
import "./Interfaces/Balancer/IBalancerQueries.sol";

contract EPendleSY is SYBaseWithRewards {
    using SafeERC20 for IERC20;

    struct ConstructorParams {
        address pendle;
        address eqb;
        address xEqb;
        address weth;
        address ePendleRewardPool;
        address smartConvertor;
        address balancerVault;
        address balancerQueries;
        bytes32 balancerWethPendlePoolId;
    }

    address public immutable pendle;
    address public immutable ePendle;
    address public immutable eqb;
    address public immutable xEqb;
    address public immutable weth;
    IBaseRewardPool public immutable ePendleRewardPool;
    address public immutable balancerVault;
    IBalancerQueries public immutable balancerQueries;
    bytes32 public immutable balancerWethPendlePoolId;
    ISmartConvertor public smartConvertor;

    constructor(
        string memory _name,
        string memory _symbol,
        address _ePendle,
        ConstructorParams memory _constructorParams
    ) SYBaseWithRewards(_name, _symbol, _ePendle) {
        pendle = _constructorParams.pendle;
        ePendle = _ePendle;
        eqb = _constructorParams.eqb;
        xEqb = _constructorParams.xEqb;
        weth = _constructorParams.weth;
        ePendleRewardPool = IBaseRewardPool(
            _constructorParams.ePendleRewardPool
        );
        smartConvertor = ISmartConvertor(_constructorParams.smartConvertor);

        balancerVault = _constructorParams.balancerVault;
        balancerQueries = IBalancerQueries(_constructorParams.balancerQueries);
        balancerWethPendlePoolId = _constructorParams.balancerWethPendlePoolId;

        _safeApproveInf(ePendle, _constructorParams.ePendleRewardPool);
        _safeApproveInf(pendle, _constructorParams.smartConvertor);
        _safeApproveInf(ePendle, _constructorParams.smartConvertor);
    }

    /**
     * @notice mint shares based on the deposited base tokens
     * @param tokenIn token address to be deposited
     * @param amountToDeposit amount of tokens to deposit
     * @return amountSharesOut amount of shares minted
     */
    function _deposit(
        address tokenIn,
        uint256 amountToDeposit
    ) internal virtual override returns (uint256 amountSharesOut) {
        if (tokenIn == pendle) {
            _harvestAndCompound(amountToDeposit);
        } else {
            _harvestAndCompound(0);
        }

        uint256 ePendleReceived = 0;
        if (tokenIn == pendle) {
            ePendleReceived = smartConvertor.deposit(amountToDeposit);
        } else if (tokenIn == ePendle) {
            ePendleReceived = amountToDeposit;
        }

        ePendleRewardPool.stake(ePendleReceived);

        // Using total assets before deposit as shares not minted yet
        amountSharesOut = _calcSharesOut(
            ePendleReceived,
            totalSupply(),
            getTotalAssetOwned() - ePendleReceived
        );
    }

    function _redeem(
        address receiver,
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal virtual override returns (uint256 amountTokenOut) {
        _harvestAndCompound(0);
        uint256 totalAsset = getTotalAssetOwned();

        uint256 priorTotalSupply = totalSupply() + amountSharesToRedeem;
        amountTokenOut = (amountSharesToRedeem * totalAsset) / priorTotalSupply;

        ePendleRewardPool.withdraw(amountTokenOut);
        if (tokenOut == ePendle) {
            _transferOut(tokenOut, receiver, amountTokenOut);
        } else if (tokenOut == pendle) {
            // swap ePendle for pendle and send to receiver
            amountTokenOut = smartConvertor.swapEPendleForPendle(
                amountTokenOut,
                0,
                receiver
            );
        }
    }

    /*///////////////////////////////////////////////////////////////
                               EXCHANGE-RATE
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev See {IStandardizedYield-exchangeRate}
     */

    function exchangeRate() public view virtual override returns (uint256) {
        return (getTotalAssetOwned() * 1e18) / totalSupply();
    }

    function getTotalAssetOwned()
        public
        view
        returns (uint256 totalAssetOwned)
    {
        uint256 stakedAmount = ePendleRewardPool.balanceOf(address(this));
        uint256 earnedWeth = ePendleRewardPool.earned(address(this), weth);
        uint256 earnedPendle = ePendleRewardPool.earned(address(this), pendle);
        totalAssetOwned =
            stakedAmount +
            smartConvertor.estimateTotalConversion(
                earnedPendle + _previewWethToPendle(earnedWeth)
            ) +
            _selfBalance(ePendle);
    }

    function _swapWETH2Pendle(uint256 _amount) internal returns (uint256) {
        if (_amount == 0) {
            return _amount;
        }
        IBalancerVault.SingleSwap memory singleSwap;
        singleSwap.poolId = balancerWethPendlePoolId;
        singleSwap.kind = IBalancerVault.SwapKind.GIVEN_IN;
        singleSwap.assetIn = IAsset(weth);
        singleSwap.assetOut = IAsset(pendle);
        singleSwap.amount = _amount;

        IBalancerVault.FundManagement memory funds;
        funds.sender = address(this);
        funds.fromInternalBalance = false;
        funds.recipient = payable(address(this));
        funds.toInternalBalance = false;

        IERC20(weth).safeApprove(balancerVault, _amount);
        return
            IBalancerVault(balancerVault).swap(
                singleSwap,
                funds,
                0,
                block.timestamp
            );
    }

    /*///////////////////////////////////////////////////////////////
                            AUTOCOMPOUND FEATURE
    //////////////////////////////////////////////////////////////*/

    function harvestAndCompound() external {
        _harvestAndCompound(0);
    }

    function _harvestAndCompound(uint256 amountPendleToNotCompound) internal {
        // get reward
        ePendleRewardPool.getReward(address(this));
        // swap weth to pendle if exists
        _swapWETH2Pendle(_selfBalance(weth));
        // convert & stake
        uint256 pendleAmount = _selfBalance(pendle) - amountPendleToNotCompound;
        if (pendleAmount > 0) {
            smartConvertor.deposit(pendleAmount);
            ePendleRewardPool.stake(_selfBalance(ePendle));
        }
    }

    /*///////////////////////////////////////////////////////////////
                               REWARDS-RELATED
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev See {IStandardizedYield-getRewardTokens}
     */

    function _getRewardTokens()
        internal
        view
        override
        returns (address[] memory res)
    {
        res = new address[](2);
        res[0] = eqb;
        res[1] = xEqb;
    }

    function _redeemExternalReward() internal override {
        _harvestAndCompound(0);
    }

    /*///////////////////////////////////////////////////////////////
                    PREVIEW-RELATED
    //////////////////////////////////////////////////////////////*/

    function _previewDeposit(
        address tokenIn,
        uint256 amountTokenToDeposit
    ) internal view override returns (uint256 amountSharesOut) {
        if (amountTokenToDeposit == 0) {
            return 0;
        }
        uint256 totalAsset = getTotalAssetOwned();

        if (tokenIn == ePendle) {
            amountSharesOut = _calcSharesOut(
                amountTokenToDeposit,
                totalSupply(),
                totalAsset
            );
        } else if (tokenIn == pendle) {
            amountSharesOut = _calcSharesOut(
                smartConvertor.estimateTotalConversion(amountTokenToDeposit),
                totalSupply(),
                totalAsset
            );
        }
    }

    function _previewWethToPendle(
        uint256 amount
    ) internal view returns (uint256) {
        if (amount == 0) {
            return 0;
        }
        IBalancerVault.SingleSwap memory singleSwap;
        singleSwap.poolId = balancerWethPendlePoolId;
        singleSwap.kind = IBalancerVault.SwapKind.GIVEN_IN;
        singleSwap.assetIn = IAsset(weth);
        singleSwap.assetOut = IAsset(pendle);
        singleSwap.amount = amount;

        IBalancerVault.FundManagement memory funds;
        funds.sender = address(this);
        funds.fromInternalBalance = false;
        funds.recipient = payable(address(this));
        funds.toInternalBalance = false;

        return balancerQueries.querySwap(singleSwap, funds);
    }

    function _previewRedeem(
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal view override returns (uint256 amountTokenOut) {
        if (amountSharesToRedeem == 0) {
            return 0;
        }
        uint256 totalAsset = getTotalAssetOwned();
        uint256 ePendleOut = (amountSharesToRedeem * totalAsset) /
            totalSupply();

        if (tokenOut == ePendle) {
            amountTokenOut = ePendleOut;
        } else if (tokenOut == pendle) {
            amountTokenOut = smartConvertor.estimateOutAmount(
                ePendle,
                ePendleOut
            );
        }
    }

    function _calcSharesOut(
        uint256 _ePendleReceived,
        uint256 _totalSupply,
        uint256 _totalAssetPrior
    ) internal view virtual returns (uint256) {
        if (_totalAssetPrior == 0 || _totalSupply == 0) {
            return _ePendleReceived;
        } else {
            return (_ePendleReceived * _totalSupply) / _totalAssetPrior;
        }
    }

    /*///////////////////////////////////////////////////////////////
                MISC FUNCTIONS FOR METADATA
    //////////////////////////////////////////////////////////////*/

    function assetInfo()
        external
        view
        returns (AssetType assetType, address assetAddress, uint8 assetDecimals)
    {
        return (AssetType.TOKEN, ePendle, IERC20Metadata(ePendle).decimals());
    }

    function getTokensIn()
        public
        view
        virtual
        override
        returns (address[] memory res)
    {
        res = new address[](2);
        res[0] = pendle;
        res[1] = ePendle;
    }

    function getTokensOut()
        public
        view
        virtual
        override
        returns (address[] memory res)
    {
        res = getTokensIn();
    }

    function isValidTokenIn(
        address token
    ) public view virtual override returns (bool) {
        return token == ePendle || token == pendle;
    }

    function isValidTokenOut(
        address token
    ) public view virtual override returns (bool) {
        return token == ePendle || token == pendle;
    }
}