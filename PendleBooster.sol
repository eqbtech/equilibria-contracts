// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./Interfaces/IPendleBooster.sol";
import "./Interfaces/IPendleProxy.sol";
import "./Interfaces/IDepositToken.sol";
import "./Interfaces/IPendleDepositor.sol";
import "./Interfaces/IEquibiliaToken.sol";
import "./Interfaces/IBaseRewardPool.sol";
import "@shared/lib-contracts-v0.8/contracts/Dependencies/TransferHelper.sol";

contract PendleBooster is IPendleBooster, OwnableUpgradeable {
    using SafeERC20 for IERC20;
    using TransferHelper for address;
    using EnumerableSet for EnumerableSet.AddressSet;

    address public pendle;

    uint256 public vlEqbIncentive; // incentive to eqb lockers
    uint256 public ePendleIncentive; //incentive to pendle stakers
    uint256 public eqbIncentive; //incentive to eqb stakers
    uint256 public platformFee; //possible fee to build treasury
    uint256 public constant MaxFees = 2500;
    uint256 public constant FEE_DENOMINATOR = 10000;

    address public pendleProxy;
    address public eqb;
    address public vlEqb;
    address public treasury;
    address public eqbRewardPool; //eqb reward pool
    address public ePendleRewardPool; //ePendle rewards(pendle)

    bool public isShutdown;

    struct PoolInfo {
        address market;
        address token;
        address rewardPool;
        bool shutdown;
    }

    //index(pid) -> pool
    PoolInfo[] public override poolInfo;

    address public pendleDepositor;
    address public ePendle;

    address public smartConvertor;

    uint256 public earmarkIncentive;

    function initialize() public initializer {
        __Ownable_init();
    }

    /// SETTER SECTION ///

    function setParams(
        address _pendle,
        address _pendleProxy,
        address _pendleDepositor,
        address _ePendle,
        address _eqb,
        address _vlEqb,
        address _eqbRewardPool,
        address _ePendleRewardPool,
        address _treasury
    ) external onlyOwner {
        require(pendleProxy == address(0), "params has already been set");

        require(_pendle != address(0), "invalid _pendle!");
        require(_pendleProxy != address(0), "invalid _pendleProxy!");
        require(_pendleDepositor != address(0), "invalid _pendleDepositor!");
        require(_ePendle != address(0), "invalid _ePendle!");
        require(_eqb != address(0), "invalid _eqb!");
        require(_vlEqb != address(0), "invalid _vlEqb!");
        require(_eqbRewardPool != address(0), "invalid _eqbRewardPool!");
        require(
            _ePendleRewardPool != address(0),
            "invalid _ePendleRewardPool!"
        );
        require(_treasury != address(0), "invalid _treasury!");

        isShutdown = false;

        pendle = _pendle;

        pendleProxy = _pendleProxy;
        pendleDepositor = _pendleDepositor;
        ePendle = _ePendle;
        eqb = _eqb;
        vlEqb = _vlEqb;

        eqbRewardPool = _eqbRewardPool;
        ePendleRewardPool = _ePendleRewardPool;

        treasury = _treasury;

        vlEqbIncentive = 500;
        ePendleIncentive = 1000;
        eqbIncentive = 100;
        platformFee = 100;
    }

    function setFees(
        uint256 _vlEqbIncentive,
        uint256 _ePendleIncentive,
        uint256 _eqbIncentive,
        uint256 _platformFee
    ) external onlyOwner {
        uint256 total = _ePendleIncentive +
            _vlEqbIncentive +
            _eqbIncentive +
            _platformFee;
        require(total <= MaxFees, ">MaxFees");

        //values must be within certain ranges
        require(
            _vlEqbIncentive >= 0 && _vlEqbIncentive <= 700,
            "invalid _vlEqbIncentive"
        );
        require(
            _ePendleIncentive >= 800 && _ePendleIncentive <= 1500,
            "invalid _ePendleIncentive"
        );
        require(
            _eqbIncentive >= 0 && _eqbIncentive <= 500,
            "invalid _eqbIncentive"
        );
        require(
            _platformFee >= 0 && _platformFee <= 1000,
            "invalid _platformFee"
        );

        vlEqbIncentive = _vlEqbIncentive;
        ePendleIncentive = _ePendleIncentive;
        eqbIncentive = _eqbIncentive;
        platformFee = _platformFee;
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    function setSmartConvertor(address _smartConvertor) external onlyOwner {
        smartConvertor = _smartConvertor;
    }

    function setEarmarkIncentive(uint256 _earmarkIncentive) external onlyOwner {
        require(
            _earmarkIncentive >= 10 && _earmarkIncentive <= 100,
            "invalid _earmarkIncentive"
        );
        earmarkIncentive = _earmarkIncentive;
    }

    /// END SETTER SECTION ///

    function poolLength() external view override returns (uint256) {
        return poolInfo.length;
    }

    // create a new pool
    function addPool(
        address _market,
        address _token,
        address _rewardPool
    ) external onlyOwner {
        require(!isShutdown, "!add");

        require(
            IPendleProxy(pendleProxy).isValidMarket(_market),
            "invalid _market"
        );

        // the next pool's pid
        uint256 pid = poolInfo.length;

        // config pendle rewards
        IBaseRewardPool(_rewardPool).setParams(
            address(this),
            pid,
            _token,
            pendle
        );

        // add the new pool
        poolInfo.push(
            PoolInfo({
                market: _market,
                token: _token,
                rewardPool: _rewardPool,
                shutdown: false
            })
        );
    }

    // shutdown pool
    function shutdownPool(uint256 _pid) public onlyOwner {
        PoolInfo storage pool = poolInfo[_pid];
        require(!pool.shutdown, "already shutdown!");

        pool.shutdown = true;
    }

    // shutdown this contract.
    // only allow withdrawals
    function shutdownSystem() external onlyOwner {
        isShutdown = true;

        for (uint256 i = 0; i < poolInfo.length; i++) {
            PoolInfo storage pool = poolInfo[i];
            if (pool.shutdown) {
                continue;
            }

            shutdownPool(i);
        }
    }

    // deposit market tokens and stake
    function deposit(
        uint256 _pid,
        uint256 _amount,
        bool _stake
    ) public override {
        require(!isShutdown, "shutdown");
        PoolInfo memory pool = poolInfo[_pid];
        require(pool.shutdown == false, "pool is closed");

        // send to proxy
        address market = pool.market;
        IERC20(market).safeTransferFrom(msg.sender, pendleProxy, _amount);

        _earmarkRewards(_pid, address(0));

        address token = pool.token;
        if (_stake) {
            // mint here and send to rewards on user behalf
            IDepositToken(token).mint(address(this), _amount);
            address rewardContract = pool.rewardPool;
            _approveTokenIfNeeded(token, rewardContract, _amount);
            IBaseRewardPool(rewardContract).stakeFor(msg.sender, _amount);
        } else {
            // add user balance directly
            IDepositToken(token).mint(msg.sender, _amount);
        }

        emit Deposited(msg.sender, _pid, _amount);
    }

    //deposit all market tokens and stake
    function depositAll(uint256 _pid, bool _stake) external {
        address market = poolInfo[_pid].market;
        uint256 balance = IERC20(market).balanceOf(msg.sender);
        deposit(_pid, balance, _stake);
    }

    // withdraw market tokens
    function _withdraw(
        uint256 _pid,
        uint256 _amount,
        address _from,
        address _to
    ) internal {
        PoolInfo memory pool = poolInfo[_pid];
        address market = pool.market;

        address token = pool.token;
        IDepositToken(token).burn(_from, _amount);

        // return market tokens
        IPendleProxy(pendleProxy).withdraw(market, _to, _amount);

        emit Withdrawn(_to, _pid, _amount);
    }

    function withdraw(uint256 _pid, uint256 _amount) public override {
        _withdraw(_pid, _amount, msg.sender, msg.sender);
    }

    function withdrawAll(uint256 _pid) external {
        address token = poolInfo[_pid].token;
        uint256 userBal = IERC20(token).balanceOf(msg.sender);
        withdraw(_pid, userBal);
    }

    // disperse pendle and extra rewards to reward contracts
    function _earmarkRewards(uint256 _pid, address _caller) internal {
        PoolInfo memory pool = poolInfo[_pid];
        address rewardContract = pool.rewardPool;

        (
            address[] memory rewardTokens,
            uint256[] memory rewardAmounts
        ) = IPendleProxy(pendleProxy).claimRewards(pool.market);

        _dispersePendle(_pid, _caller);

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address rewardToken = rewardTokens[i];
            uint256 rewardAmount = rewardAmounts[i];
            if (rewardToken == address(0) || rewardAmount == 0) {
                continue;
            }
            emit RewardClaimed(_pid, rewardToken, rewardAmount);
            if (rewardToken == pendle) {
                // pendle was dispersed above
                continue;
            }
            if (AddressLib.isPlatformToken(rewardToken)) {
                IRewards(rewardContract).queueNewRewards{value: rewardAmount}(
                    rewardToken,
                    rewardAmount
                );
            } else {
                _approveTokenIfNeeded(
                    rewardToken,
                    rewardContract,
                    rewardAmount
                );
                IRewards(rewardContract).queueNewRewards(
                    rewardToken,
                    rewardAmount
                );
            }
        }
    }

    function _dispersePendle(uint256 _pid, address _caller) internal {
        PoolInfo memory pool = poolInfo[_pid];

        uint256 pendleBal = IERC20(pendle).balanceOf(address(this));
        if (pendleBal == 0) {
            return;
        }
        uint256 vlEqbIncentiveAmount = (pendleBal * vlEqbIncentive) /
            FEE_DENOMINATOR;
        uint256 ePendleIncentiveAmount = (pendleBal * ePendleIncentive) /
            FEE_DENOMINATOR;
        uint256 eqbIncentiveAmount = (pendleBal * eqbIncentive) /
            FEE_DENOMINATOR;

        uint256 earmarkIncentiveAmount = 0;
        if (_caller != address(0) && earmarkIncentive > 0) {
            earmarkIncentiveAmount =
                (pendleBal * earmarkIncentive) /
                FEE_DENOMINATOR;

            // send incentives for calling
            IERC20(pendle).safeTransfer(_caller, earmarkIncentiveAmount);

            emit EarmarkIncentiveSent(_pid, _caller, earmarkIncentiveAmount);
        }

        // send treasury
        uint256 platform = 0;
        if (platformFee > 0) {
            //only subtract after address condition check
            platform = (pendleBal * platformFee) / FEE_DENOMINATOR;
            IERC20(pendle).safeTransfer(treasury, platform);
        }

        //remove incentives from balance
        pendleBal =
            pendleBal -
            vlEqbIncentiveAmount -
            ePendleIncentiveAmount -
            eqbIncentiveAmount -
            earmarkIncentiveAmount -
            platform;

        //send pendle to lp provider reward contract
        address rewardContract = pool.rewardPool;
        _approveTokenIfNeeded(pendle, rewardContract, pendleBal);
        IRewards(rewardContract).queueNewRewards(pendle, pendleBal);

        //send ePendle to vlEqb
        if (vlEqbIncentiveAmount > 0) {
            uint256 ePendleAmount = _convertPendleToEPendle(
                vlEqbIncentiveAmount
            );

            _approveTokenIfNeeded(ePendle, vlEqb, ePendleAmount);
            IRewards(vlEqb).queueNewRewards(ePendle, ePendleAmount);
        }

        //send pendle to ePendle reward contract
        if (ePendleIncentiveAmount > 0) {
            _approveTokenIfNeeded(
                pendle,
                ePendleRewardPool,
                ePendleIncentiveAmount
            );
            IRewards(ePendleRewardPool).queueNewRewards(
                pendle,
                ePendleIncentiveAmount
            );
        }

        //send ePendle to eqb reward contract
        if (eqbIncentiveAmount > 0) {
            uint256 ePendleAmount = _convertPendleToEPendle(eqbIncentiveAmount);

            _approveTokenIfNeeded(ePendle, eqbRewardPool, ePendleAmount);
            IRewards(eqbRewardPool).queueNewRewards(ePendle, ePendleAmount);
        }
    }

    function earmarkRewards(uint256 _pid) external {
        require(!isShutdown, "shutdown");
        PoolInfo memory pool = poolInfo[_pid];
        require(pool.shutdown == false, "pool is closed");

        _earmarkRewards(_pid, msg.sender);
    }

    // callback from reward contract when pendle is received.
    function rewardClaimed(
        uint256 _pid,
        address _account,
        address _token,
        uint256 _amount
    ) external override {
        address rewardContract = poolInfo[_pid].rewardPool;
        require(
            msg.sender == rewardContract || msg.sender == ePendleRewardPool,
            "!auth"
        );

        if (_token != pendle || isShutdown) {
            return;
        }

        //mint reward tokens
        IEquibiliaToken(eqb).mint(_account, _amount);
    }

    function _convertPendleToEPendle(
        uint256 _amount
    ) internal returns (uint256) {
        _approveTokenIfNeeded(pendle, pendleDepositor, _amount);
        IPendleDepositor(pendleDepositor).deposit(_amount, false);
        return _amount;
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

    receive() external payable {}
}
