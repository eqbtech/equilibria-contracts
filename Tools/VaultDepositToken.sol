// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../Dependencies/EqbConstants.sol";

import "../Interfaces/Pendle/IPMarket.sol";
import "../Interfaces/Pendle/IPendleRouterV3.sol";
import "../Interfaces/Pendle/IPSwapAggregator.sol";
import "../Interfaces/IEqbConfig.sol";
import "../Interfaces/IBaseRewardPool.sol";
import "../Interfaces/IPendleBooster.sol";
import "../Interfaces/IVaultDepositToken.sol";

/**
 * @dev Implementation of a vault to deposit funds for yield optimizing.
 * This is the contract that receives funds and that users interface with.
 * The yield optimizing strategy itself is implemented in a separate 'Strategy.sol' contract.
 */
contract VaultDepositToken is
    IVaultDepositToken,
    ERC20Upgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    address public pendle;
    IEqbConfig public eqbConfig;
    IPendleBooster public booster;
    uint256 public override pid;
    address public market;
    address public token;
    address public rewardPool;

    bool public userHarvest;

    event Deposited(address indexed user, uint256 shares, uint256 amount);
    event Withdrawn(address indexed user, uint256 shares, uint256 amount);
    event Harvested(uint256 amount);

    /**
     * @dev Sets the value of {token} to the token that the vault will
     * hold as underlying value. It initializes the vault's own 'moo' token.
     * This token is minted when someone does a deposit. It is burned in order
     * to withdraw the corresponding portion of the underlying assets.
     */
    function initialize(
        address _pendle,
        address _eqbConfig,
        address _booster,
        uint256 _pid
    ) public initializer {
        __AccessControl_init();
        __ReentrancyGuard_init_unchained();

        pendle = _pendle;
        eqbConfig = IEqbConfig(_eqbConfig);
        booster = IPendleBooster(_booster);
        pid = _pid;
        (market, token, rewardPool, ) = booster.poolInfo(_pid);

        (address _SY, , ) = IPMarket(market).readTokens();

        __ERC20_init_unchained(
            string(abi.encodePacked("Auto Compounder EQB ", ERC20(_SY).name())),
            string(abi.encodePacked("ac-EQB ", ERC20(_SY).symbol()))
        );

        userHarvest = true;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    modifier updateReward() {
        if (userHarvest) {
            harvest();
        }

        _;
    }

    function want() public view returns (IERC20) {
        return IERC20(token);
    }

    /**
     * @dev It calculates the total underlying value of {token} held by the system.
     * It takes into account the vault contract balance, the strategy contract balance
     *  and the balance deployed in other contracts as part of the strategy.
     */
    function balance() public view returns (uint) {
        return
            want().balanceOf(address(this)) +
            IBaseRewardPool(rewardPool).balanceOf(address(this));
    }

    /**
     * @dev Custom logic in here for how much the vault allows to be borrowed.
     * We return 100% of tokens for now. Under certain conditions we might
     * want to keep some of the system funds at hand in the vault, instead
     * of putting them to work.
     */
    function available() public view returns (uint256) {
        return want().balanceOf(address(this));
    }

    /**
     * @dev Function for various UIs to display the current value of one of our yield tokens.
     * Returns an uint256 with 18 decimals of how much underlying asset one vault share represents.
     */
    function getPricePerFullShare() public view returns (uint256) {
        return totalSupply() == 0 ? 1e18 : (balance() * 1e18) / totalSupply();
    }

    /**
     * @dev A helper function to call deposit() with all the sender's funds.
     */
    function depositAll() external returns (uint256) {
        return deposit(want().balanceOf(msg.sender));
    }

    /**
     * @dev The entrypoint of funds into the system. People deposit with this function
     * into the vault. The vault is then in charge of sending funds into the strategy.
     */
    function deposit(
        uint _amount
    ) public override nonReentrant updateReward returns (uint256) {
        require(_amount > 0, "amount must be greater than zero");
        uint256 _pool = balance();
        want().safeTransferFrom(msg.sender, address(this), _amount);
        earn();
        uint256 _after = balance();
        _amount = _after - _pool; // Additional check for deflationary tokens
        uint256 shares = 0;
        if (totalSupply() == 0) {
            shares = _amount;
        } else {
            shares = (_amount * totalSupply()) / _pool;
        }
        _mint(msg.sender, shares);

        emit Deposited(msg.sender, shares, _amount);

        return shares;
    }

    /**
     * @dev Function to send funds into the strategy and put them to work. It's primarily called
     * by the vault's deposit() function.
     */
    function earn() public {
        uint _bal = available();
        _approveTokenIfNeeded(token, rewardPool, _bal);
        IBaseRewardPool(rewardPool).stake(_bal);
    }

    /**
     * @dev A helper function to call withdraw() with all the sender's funds.
     */
    function withdrawAll() external returns (uint256) {
        return withdraw(balanceOf(msg.sender));
    }

    /**
     * @dev Function to exit the system. The vault will withdraw the required tokens
     * from the strategy and pay up the token holder. A proportional number of IOU
     * tokens are burned in the process.
     */
    function withdraw(
        uint256 _shares
    ) public override updateReward returns (uint256) {
        require(_shares > 0, "shares must be greater than zero");

        uint256 r = (balance() * _shares) / totalSupply();
        _burn(msg.sender, _shares);

        uint b = want().balanceOf(address(this));
        if (b < r) {
            uint _withdraw = r - b;
            IBaseRewardPool(rewardPool).withdraw(_withdraw);
            uint _after = want().balanceOf(address(this));
            uint _diff = _after - b;
            if (_diff < _withdraw) {
                r = b + _diff;
            }
        }

        want().safeTransfer(msg.sender, r);

        emit Withdrawn(msg.sender, _shares, r);

        return r;
    }

    function harvest() public {
        IBaseRewardPool(rewardPool).getReward(address(this));
        uint256 pendleAmount = IERC20(pendle).balanceOf(address(this));
        if (pendleAmount > 0) {
            address pendleRouterV3 = eqbConfig.getContract(
                EqbConstants.PENDLE_ROUTER_V3
            );
            _approveTokenIfNeeded(pendle, pendleRouterV3, pendleAmount);
            (uint256 netLpOut, , ) = IPendleRouterV3(pendleRouterV3)
                .addLiquiditySingleToken(
                    address(this),
                    market,
                    0,
                    IPendleRouterV3.ApproxParams({
                        guessMin: 0,
                        guessMax: type(uint256).max,
                        guessOffchain: 0,
                        maxIteration: 256,
                        eps: 1e15
                    }),
                    IPendleRouterV3.TokenInput({
                        tokenIn: pendle,
                        netTokenIn: pendleAmount,
                        tokenMintSy: pendle,
                        pendleSwap: address(0),
                        swapData: SwapData({
                            swapType: SwapType.NONE,
                            extRouter: address(0),
                            extCalldata: "",
                            needScale: false
                        })
                    }),
                    IPendleRouterV3.LimitOrderData({
                        limitRouter: address(0),
                        epsSkipMarket: 0,
                        normalFills: new FillOrderParams[](0),
                        flashFills: new FillOrderParams[](0),
                        optData: ""
                    })
                );

            if (netLpOut > 0) {
                _approveTokenIfNeeded(market, address(booster), netLpOut);
                booster.deposit(pid, netLpOut, false);
            }

            emit Harvested(netLpOut);
        }
    }

    /**
     * @dev Rescues random funds stuck that the strat can't handle.
     * @param _token address of the token to rescue.
     */
    function inCaseTokensGetStuck(
        address _token
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_token != address(want()), "!token");

        uint256 amount = IERC20Upgradeable(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, amount);
    }

    function setUserHarvest(
        bool _userHarvest
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        userHarvest = _userHarvest;
    }

    function _approveTokenIfNeeded(
        address _token,
        address _to,
        uint256 _amount
    ) internal {
        if (IERC20(_token).allowance(address(this), _to) < _amount) {
            IERC20(_token).safeApprove(_to, 0);
            IERC20(_token).safeApprove(_to, type(uint256).max);
        }
    }
}
