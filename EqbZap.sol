// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./Interfaces/Pendle/IPMarket.sol";
import "./Interfaces/Pendle/IPendleRouter.sol";
import "./Interfaces/Pendle/IPendleRouterV3.sol";
import "./Interfaces/IBaseRewardPool.sol";
import "./Interfaces/IPendleBooster.sol";
import "./Interfaces/IEqbConfig.sol";
import "./Interfaces/IVaultDepositToken.sol";
import "./Dependencies/EqbConstants.sol";

contract EqbZap is OwnableUpgradeable {
    using SafeERC20 for IERC20;

    address internal constant NATIVE = address(0);

    IPendleBooster public booster;
    address public pendleRouter;
    IEqbConfig public eqbConfig;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __Ownable_init();
    }

    function setParams(
        address _booster,
        address _pendleRouter
    ) external onlyOwner {
        require(_booster != address(0), "invalid _booster");
        require(_pendleRouter != address(0), "invalid _pendleRouter");

        booster = IPendleBooster(_booster);
        pendleRouter = _pendleRouter;
    }

    function setEqbConfig(address _eqbConfig) external onlyOwner {
        require(_eqbConfig != address(0), "invalid _eqbConfig");
        eqbConfig = IEqbConfig(_eqbConfig);
    }

    function depositToVaultDepositToken(
        address _vaultDepositToken,
        uint256 _amount
    ) external {
        uint256 pid = IVaultDepositToken(_vaultDepositToken).pid();
        (address market, address token, , ) = booster.poolInfo(pid);
        IERC20(market).safeTransferFrom(msg.sender, address(this), _amount);
        _approveTokenIfNeeded(market, address(booster), _amount);
        booster.deposit(pid, _amount, false);
        _approveTokenIfNeeded(token, _vaultDepositToken, _amount);
        uint256 shares = IVaultDepositToken(_vaultDepositToken).deposit(
            _amount
        );
        IERC20(_vaultDepositToken).safeTransfer(msg.sender, shares);
    }

    function zapIn(
        uint256 _pid,
        uint256 _minLpOut,
        IPendleRouter.ApproxParams calldata _guessPtReceivedFromSy,
        IPendleRouter.TokenInput calldata _input,
        bool _stake,
        address _vaultDepositToken
    ) external payable {
        (address market, , , ) = booster.poolInfo(_pid);
        _transferIn(_input.tokenIn, msg.sender, _input.netTokenIn);
        _approveTokenIfNeeded(_input.tokenIn, pendleRouter, _input.netTokenIn);
        (uint256 netLpOut, ) = IPendleRouter(pendleRouter)
            .addLiquiditySingleToken{
            value: _input.tokenIn == NATIVE ? _input.netTokenIn : 0
        }(address(this), market, _minLpOut, _guessPtReceivedFromSy, _input);
        _deposit(_pid, netLpOut, _stake, _vaultDepositToken);
    }

    function withdraw(uint256 _pid, uint256 _amount) external {
        (address market, address token, address rewardPool, ) = booster
            .poolInfo(_pid);
        IBaseRewardPool(rewardPool).withdrawFor(msg.sender, _amount);
        IERC20(token).safeTransferFrom(msg.sender, address(this), _amount);
        booster.withdraw(_pid, _amount);
        IERC20(market).safeTransfer(msg.sender, _amount);
    }

    function withdrawFromVaultDepositToken(
        address _vaultDepositToken,
        uint256 _shares
    ) external {
        IERC20(_vaultDepositToken).safeTransferFrom(
            msg.sender,
            address(this),
            _shares
        );
        uint256 amount = IVaultDepositToken(_vaultDepositToken).withdraw(
            _shares
        );
        uint256 pid = IVaultDepositToken(_vaultDepositToken).pid();
        booster.withdraw(pid, amount);
        (address market, , , ) = booster.poolInfo(pid);
        IERC20(market).safeTransfer(msg.sender, amount);
    }

    function zapOut(
        uint256 _pid,
        uint256 _amount,
        IPendleRouter.TokenOutput calldata _output,
        bool _stake,
        address _vaultDepositToken
    ) external {
        _amount = _withdraw(_pid, _amount, _stake, _vaultDepositToken);
        (address market, , , ) = booster.poolInfo(_pid);

        _approveTokenIfNeeded(market, pendleRouter, _amount);
        IPendleRouter(pendleRouter).removeLiquiditySingleToken(
            msg.sender,
            market,
            _amount,
            _output
        );
    }

    function claimRewards(uint256[] calldata _pids) external {
        for (uint256 i = 0; i < _pids.length; i++) {
            (, , address rewardPool, ) = booster.poolInfo(_pids[i]);
            require(rewardPool != address(0), "invalid _pids");
            IBaseRewardPool(rewardPool).getReward(msg.sender);
        }
    }

    // PendleRouterV3
    function zapInV3SinglePt(
        uint256 _pid,
        uint256 _netPtIn,
        uint256 _minLpOut,
        IPendleRouterV3.ApproxParams calldata _guessPtSwapToSy,
        IPendleRouterV3.LimitOrderData calldata _limit,
        bool _stake,
        address _vaultDepositToken
    ) external {
        address pendleRouterV3 = eqbConfig.getContract(
            EqbConstants.PENDLE_ROUTER_V3
        );
        (address market, , , ) = booster.poolInfo(_pid);
        (, address PT, ) = IPMarket(market).readTokens();
        _transferIn(PT, msg.sender, _netPtIn);
        _approveTokenIfNeeded(PT, pendleRouterV3, _netPtIn);
        (uint256 netLpOut, ) = IPendleRouterV3(pendleRouterV3)
            .addLiquiditySinglePt(
                address(this),
                market,
                _netPtIn,
                _minLpOut,
                _guessPtSwapToSy,
                _limit
            );
        _deposit(_pid, netLpOut, _stake, _vaultDepositToken);
    }

    function zapInV3SingleToken(
        uint256 _pid,
        uint256 _minLpOut,
        IPendleRouterV3.ApproxParams calldata _guessPtReceivedFromSy,
        IPendleRouterV3.TokenInput calldata _input,
        IPendleRouterV3.LimitOrderData calldata _limit,
        bool _stake,
        address _vaultDepositToken
    ) external payable {
        address pendleRouterV3 = eqbConfig.getContract(
            EqbConstants.PENDLE_ROUTER_V3
        );
        (address market, , , ) = booster.poolInfo(_pid);
        _transferIn(_input.tokenIn, msg.sender, _input.netTokenIn);
        _approveTokenIfNeeded(
            _input.tokenIn,
            pendleRouterV3,
            _input.netTokenIn
        );
        (uint256 netLpOut, , ) = IPendleRouterV3(pendleRouterV3)
            .addLiquiditySingleToken{
            value: _input.tokenIn == NATIVE ? _input.netTokenIn : 0
        }(
            address(this),
            market,
            _minLpOut,
            _guessPtReceivedFromSy,
            _input,
            _limit
        );
        _deposit(_pid, netLpOut, _stake, _vaultDepositToken);
    }

    function zapInV3SingleTokenKeepYt(
        uint256 _pid,
        uint256 _minLpOut,
        uint256 _minYtOut,
        IPendleRouterV3.TokenInput calldata _input,
        bool _stake,
        address _vaultDepositToken
    ) external payable {
        address pendleRouterV3 = eqbConfig.getContract(
            EqbConstants.PENDLE_ROUTER_V3
        );
        (address market, , , ) = booster.poolInfo(_pid);
        (, , address YT) = IPMarket(market).readTokens();
        _transferIn(_input.tokenIn, msg.sender, _input.netTokenIn);
        _approveTokenIfNeeded(
            _input.tokenIn,
            pendleRouterV3,
            _input.netTokenIn
        );
        (uint256 netLpOut, uint256 netYtOut, , ) = IPendleRouterV3(
            pendleRouterV3
        ).addLiquiditySingleTokenKeepYt{
            value: _input.tokenIn == NATIVE ? _input.netTokenIn : 0
        }(address(this), market, _minLpOut, _minYtOut, _input);
        IERC20(YT).safeTransfer(msg.sender, netYtOut);
        _deposit(_pid, netLpOut, _stake, _vaultDepositToken);
    }

    function zapOutV3SinglePt(
        uint256 _pid,
        uint256 _amount,
        uint256 _minPtOut,
        IPendleRouterV3.ApproxParams calldata _guessPtReceivedFromSy,
        IPendleRouterV3.LimitOrderData calldata _limit,
        bool _stake,
        address _vaultDepositToken
    ) external {
        address pendleRouterV3 = eqbConfig.getContract(
            EqbConstants.PENDLE_ROUTER_V3
        );
        _amount = _withdraw(_pid, _amount, _stake, _vaultDepositToken);
        (address market, , , ) = booster.poolInfo(_pid);

        _approveTokenIfNeeded(market, pendleRouterV3, _amount);
        IPendleRouterV3(pendleRouterV3).removeLiquiditySinglePt(
            msg.sender,
            market,
            _amount,
            _minPtOut,
            _guessPtReceivedFromSy,
            _limit
        );
    }

    function zapOutV3SingleToken(
        uint256 _pid,
        uint256 _amount,
        IPendleRouterV3.TokenOutput calldata _output,
        IPendleRouterV3.LimitOrderData calldata _limit,
        bool _stake,
        address _vaultDepositToken
    ) external {
        address pendleRouterV3 = eqbConfig.getContract(
            EqbConstants.PENDLE_ROUTER_V3
        );
        _amount = _withdraw(_pid, _amount, _stake, _vaultDepositToken);
        (address market, , , ) = booster.poolInfo(_pid);

        _approveTokenIfNeeded(market, pendleRouterV3, _amount);
        IPendleRouterV3(pendleRouterV3).removeLiquiditySingleToken(
            msg.sender,
            market,
            _amount,
            _output,
            _limit
        );
    }

    function _deposit(
        uint256 _pid,
        uint256 _amount,
        bool _stake,
        address _vaultDepositToken
    ) internal {
        require(
            !(_stake && _vaultDepositToken != address(0)),
            "invalid prameters"
        );
        (address market, address token, address rewardPool, ) = booster
            .poolInfo(_pid);
        _approveTokenIfNeeded(market, address(booster), _amount);
        booster.deposit(_pid, _amount, false);

        if (_stake) {
            _approveTokenIfNeeded(token, rewardPool, _amount);
            IBaseRewardPool(rewardPool).stakeFor(msg.sender, _amount);
            return;
        }
        if (_vaultDepositToken != address(0)) {
            _approveTokenIfNeeded(token, _vaultDepositToken, _amount);
            _amount = IVaultDepositToken(_vaultDepositToken).deposit(_amount);
            IERC20(_vaultDepositToken).safeTransfer(msg.sender, _amount);
        } else {
            IERC20(token).safeTransfer(msg.sender, _amount);
        }
    }

    function _withdraw(
        uint256 _pid,
        uint256 _amount,
        bool _stake,
        address _vaultDepositToken
    ) internal returns (uint256) {
        require(
            !(_stake && _vaultDepositToken != address(0)),
            "invalid prameters"
        );
        (, address token, address rewardPool, ) = booster.poolInfo(_pid);

        if (_vaultDepositToken != address(0)) {
            IERC20(_vaultDepositToken).safeTransferFrom(
                msg.sender,
                address(this),
                _amount
            );
            _amount = IVaultDepositToken(_vaultDepositToken).withdraw(_amount);
        } else {
            if (_stake) {
                IBaseRewardPool(rewardPool).withdrawFor(msg.sender, _amount);
            }

            IERC20(token).safeTransferFrom(msg.sender, address(this), _amount);
        }

        booster.withdraw(_pid, _amount);
        return _amount;
    }

    function _transferIn(
        address _token,
        address _from,
        uint256 _amount
    ) internal {
        if (_token == NATIVE) {
            require(msg.value == _amount, "eth mismatch");
        } else if (_amount != 0) {
            require(msg.value == 0, "eth mismatch");
            IERC20(_token).safeTransferFrom(_from, address(this), _amount);
        }
    }

    function _approveTokenIfNeeded(
        address _token,
        address _to,
        uint256 _amount
    ) internal {
        if (_token == NATIVE) {
            return;
        }
        if (IERC20(_token).allowance(address(this), _to) < _amount) {
            IERC20(_token).safeApprove(_to, 0);
            IERC20(_token).safeApprove(_to, type(uint256).max);
        }
    }
}
