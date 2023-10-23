// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@pendle/core-v2/contracts/core/StandardizedYield/SYBaseWithRewards.sol";
import "./Interfaces/ISmartConvertor.sol";
import "./Interfaces/IBaseRewardPool.sol";
import "./Interfaces/Balancer/IBalancerVault.sol";

contract EPendleSY is SYBaseWithRewards {
    using SafeERC20 for IERC20;

    address public immutable pendle;
    address public immutable ePendle;
    address public immutable eqb;
    address public immutable xEqb;
    address public immutable weth;
    IBaseRewardPool public immutable ePendleRewardPool;
    address public immutable balancerVault;
    bytes32 public immutable balancerWethPendlePoolId;
    ISmartConvertor public smartConvertor;

    constructor(
        string memory _name,
        string memory _symbol,
        address _ePendle,
        address _pendle,
        address _eqb,
        address _xEqb,
        address _weth,
        address _ePendleRewardPool,
        address _smartConvertor,
        address _balancerVault,
        bytes32 _balancerWethPendlePoolId
    ) SYBaseWithRewards(_name, _symbol, _ePendle) {
        pendle = _pendle;
        ePendle = _ePendle;
        eqb = _eqb;
        xEqb = _xEqb;
        weth = _weth;
        ePendleRewardPool = IBaseRewardPool(_ePendleRewardPool);
        smartConvertor = ISmartConvertor(_smartConvertor);

        balancerVault = _balancerVault;
        balancerWethPendlePoolId = _balancerWethPendlePoolId;

        _safeApproveInf(ePendle, _ePendleRewardPool);
        _safeApproveInf(pendle, _smartConvertor);
        _safeApproveInf(ePendle, _smartConvertor);
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
        uint256 harvestedPendleAmount = _harvest();

        uint256 ePendleAmount = 0;
        uint256 ePendleReceived = 0;
        if (tokenIn == pendle) {
            ePendleAmount = smartConvertor.deposit(
                amountToDeposit + harvestedPendleAmount
            );
            ePendleReceived =
                (ePendleAmount * amountToDeposit) /
                (amountToDeposit + harvestedPendleAmount);
        } else if (tokenIn == ePendle) {
            ePendleAmount = amountToDeposit;
            ePendleReceived = amountToDeposit;
            if (harvestedPendleAmount > 0) {
                ePendleAmount += smartConvertor.deposit(harvestedPendleAmount);
            }
        }

        ePendleRewardPool.stake(ePendleAmount);

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
        harvestAndCompound();
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
        totalAssetOwned =
            ePendleRewardPool.balanceOf(address(this)) +
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

    function harvestAndCompound() public {
        _harvest();
        // convert & stake
        uint256 pendleAmount = _selfBalance(pendle);
        if (pendleAmount > 0) {
            smartConvertor.deposit(pendleAmount);
            ePendleRewardPool.stake(_selfBalance(ePendle));
        }
    }

    function _harvest() internal returns (uint256) {
        // get reward
        ePendleRewardPool.getReward(address(this));
        // swap weth to pendle if exists
        return _swapWETH2Pendle(_selfBalance(weth));
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
        harvestAndCompound();
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
                smartConvertor.previewAmountOut(pendle, amountTokenToDeposit),
                totalSupply(),
                totalAsset
            );
        }
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
            amountTokenOut = smartConvertor.previewAmountOut(
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
