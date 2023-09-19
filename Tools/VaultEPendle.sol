// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@shared/lib-contracts-v0.8/contracts/Dependencies/TransferHelper.sol";
import "../Interfaces/IBaseRewardPool.sol";
import "../Interfaces/ISmartConvertor.sol";
import "../Interfaces/Balancer/IBalancer.sol";

contract VaultEPendle is
    ERC20Upgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;
    using TransferHelper for address;

    IERC20 public pendle;
    IERC20 public ependle;
    IERC20 public weth;
    IERC20 public eqb;
    IERC20 public xEqb;
    IBalancer public balancer;
    IBaseRewardPool public ePendleRewardPool;
    ISmartConvertor public smartConvertor;

    address public feeRecipient;
    address[] public rewardTokens;
    bool public userHarvest;
    uint256 public constant FEE_PRECISION = 1e6;
    uint256 public harvestFeeRate;
    uint256 public withdrawalFeeRate;
    bytes32 private balancerPool;

    event Deposited(address indexed _user, uint256 _amount);
    event Withdrawn(
        address indexed _user,
        uint256 _share,
        uint256 _amount,
        uint256 _withdrawalFee
    );
    event Harvested(
        address indexed _rewardToken,
        uint256 _amount,
        uint256 _harvestFee
    );
    event HarvestFeeRateUpdated(uint256 _feeRate);
    event WithdrawalFeeRateUpdated(uint256 _feeRate);
    event RewardTokenAdded(address indexed _rewardToken);
    event RewardAdded(address indexed _rewardToken, uint256 _reward);
    event RewardPaid(
        address indexed _user,
        address indexed _rewardToken,
        uint256 _reward
    );

    struct Reward {
        uint256 rewardPerTokenStored;
        uint256 queuedRewards;
    }

    struct UserReward {
        uint256 userRewardPerTokenPaid;
        uint256 rewards;
    }

    mapping(address => Reward) public rewards;
    mapping(address => bool) public isRewardToken;
    mapping(address => mapping(address => UserReward)) public userRewards;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory _name,
        string memory _symbol
    ) public initializer {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        __ReentrancyGuard_init_unchained();
        __ERC20_init_unchained(_name, _symbol);
    }

    function setParams(
        address _pendle,
        address _ependle,
        address _ePendleRewardPool,
        address _feeRecipient,
        address _wethAddr,
        address _balancerAddr,
        address _smartConvertor,
        address _eqb,
        address _xEqb,
        bytes32 _balancerPool
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_pendle != address(0), "invalid _pendle!");
        require(_ependle != address(0), "invalid _ependle!");
        require(_wethAddr != address(0), "invalid _wethAddr!");
        require(_eqb != address(0), "invalid _eqb!");
        require(_xEqb != address(0), "invalid _xEqb!");
        require(_balancerAddr != address(0), "invalid _balancerAddr!");
        require(_smartConvertor != address(0), "invalid _smartConvertor!");
        require(
            _ePendleRewardPool != address(0),
            "invalid _ePendleRewardPool!"
        );
        require(_feeRecipient != address(0), "invalid _feeRecipient!");

        pendle = IERC20(_pendle);
        ependle = IERC20(_ependle);
        weth = IERC20(_wethAddr);
        eqb = IERC20(_eqb);
        xEqb = IERC20(_xEqb);
        balancer = IBalancer(_balancerAddr);
        ePendleRewardPool = IBaseRewardPool(_ePendleRewardPool);
        feeRecipient = _feeRecipient;
        balancerPool = _balancerPool;

        smartConvertor = ISmartConvertor(_smartConvertor);
        userHarvest = true;
    }

    function depositAll() external returns (uint256) {
        return deposit(ependle.balanceOf(msg.sender));
    }

    function deposit(
        uint256 _amount
    ) public nonReentrant updateReward(msg.sender) returns (uint256) {
        require(
            _amount > 0,
            "VaultEPendle deposit: amount must be greater than zero"
        );
        if (userHarvest) {
            harvest();
        }
        uint256 balanceBefore = balance();
        ependle.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 shares = 0;
        if (totalSupply() == 0) {
            shares = _amount;
        } else {
            shares = (_amount * totalSupply()) / balanceBefore;
        }
        _mint(msg.sender, shares);
        ependle.safeApprove(address(ePendleRewardPool), _amount);
        ePendleRewardPool.stake(_amount);
        emit Deposited(msg.sender, _amount);

        return shares;
    }

    function withdrawAll() external returns (uint256) {
        uint256 withdrawShare = balanceOf(msg.sender);
        uint256 withdrawAmount = 0;
        if (withdrawShare > 0) {
            withdrawAmount = withdraw(withdrawShare);
        }
        getReward(msg.sender);
        return withdrawAmount;
    }

    function withdraw(
        uint256 _shares
    ) public nonReentrant updateReward(msg.sender) returns (uint256) {
        require(
            _shares > 0,
            "VaultEPendle withdraw: amount must be greater than zero"
        );
        uint256 r = (balance() * _shares) / totalSupply();
        _burn(msg.sender, _shares);

        uint256 ependleBal = ependle.balanceOf(address(this));
        //if not sufficient, get reward from ependle reward pool
        if (ependleBal < r) {
            ePendleRewardPool.withdraw(r - ependleBal);
        }

        uint256 withdrawalFee = (r * withdrawalFeeRate) / FEE_PRECISION;
        ependle.safeTransfer(feeRecipient, withdrawalFee);
        ependle.safeTransfer(msg.sender, r - withdrawalFee);
        emit Withdrawn(msg.sender, _shares, r - withdrawalFee, withdrawalFee);

        if (userHarvest) {
            harvest();
        }

        return r - withdrawalFee;
    }

    function harvest() public {
        address[] memory rewardTokensFromPool = ePendleRewardPool
            .getRewardTokens();
        if (rewardTokensFromPool.length == 0) {
            return;
        }
        address[] memory ePendleRewardTokens = new address[](
            rewardTokensFromPool.length + 2
        );
        ePendleRewardTokens[0] = address(eqb);
        ePendleRewardTokens[1] = address(xEqb);
        for (uint256 i = 0; i < rewardTokensFromPool.length; i++) {
            if (
                rewardTokensFromPool[i] != address(eqb) &&
                rewardTokensFromPool[i] != address(xEqb)
            ) {
                ePendleRewardTokens[i + 2] = rewardTokensFromPool[i];
            }
        }

        uint256[] memory beforeBals = new uint256[](ePendleRewardTokens.length);
        uint256[] memory afterBals = new uint256[](ePendleRewardTokens.length);

        for (uint256 i = 0; i < ePendleRewardTokens.length; i++) {
            if (ePendleRewardTokens[i] != address(0)) {
                beforeBals[i] = ePendleRewardTokens[i].balanceOf(address(this));
            }
        }

        ePendleRewardPool.getReward(address(this));
        for (uint256 i = 0; i < ePendleRewardTokens.length; i++) {
            if (ePendleRewardTokens[i] != address(0)) {
                afterBals[i] = ePendleRewardTokens[i].balanceOf(address(this));
            }
        }

        for (uint256 i = 0; i < ePendleRewardTokens.length; i++) {
            if (ePendleRewardTokens[i] == address(0)) {
                continue;
            }
            //charge fees
            uint256 harvestAmount = afterBals[i] - beforeBals[i];
            if (harvestAmount <= 0) {
                continue;
            }
            uint256 harvestFee = (harvestAmount * harvestFeeRate) /
                FEE_PRECISION;
            ePendleRewardTokens[i].safeTransferToken(feeRecipient, harvestFee);
            uint256 rewardTokenAmount = harvestAmount - harvestFee;

            if (rewardTokenAmount <= 0) {
                continue;
            }
            //reinvest reward if reward token is weth
            if (address(weth) == ePendleRewardTokens[i]) {
                //step1: swap weth to pendle
                uint256 pendleAmount = _swapWETH2Pendle(rewardTokenAmount);
                //step2: swap pendle to ependle through smart convertor
                pendle.safeApprove(address(smartConvertor), pendleAmount);
                uint256 obtainedEPendle = smartConvertor.deposit(pendleAmount);
                //step3: reinvest
                ependle.safeApprove(
                    address(ePendleRewardPool),
                    obtainedEPendle
                );
                ePendleRewardPool.stake(obtainedEPendle);
            } else {
                //queue reward if reward is not weth
                _queueNewRewards(ePendleRewardTokens[i], rewardTokenAmount);
            }

            emit Harvested(
                ePendleRewardTokens[i],
                rewardTokenAmount,
                harvestFee
            );
        }
    }

    function _queueNewRewards(address _rewardToken, uint256 _rewards) internal {
        _addRewardToken(_rewardToken);

        Reward storage rewardInfo = rewards[_rewardToken];

        if (totalSupply() == 0) {
            rewardInfo.queuedRewards = rewardInfo.queuedRewards + _rewards;
            return;
        }

        _rewards = _rewards + rewardInfo.queuedRewards;
        rewardInfo.queuedRewards = 0;
        rewardInfo.rewardPerTokenStored =
            rewardInfo.rewardPerTokenStored +
            ((_rewards * 1e18) / totalSupply());

        emit RewardAdded(_rewardToken, _rewards);
    }

    function getReward(
        address _account
    ) public nonReentrant updateReward(_account) {
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address rewardToken = rewardTokens[i];
            uint256 reward = userRewards[_account][rewardToken].rewards;
            if (reward > 0) {
                userRewards[_account][rewardToken].rewards = 0;
                rewardToken.safeTransferToken(_account, reward);
                emit RewardPaid(_account, rewardToken, reward);
            }
        }
    }

    modifier updateReward(address _account) {
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address rewardToken = rewardTokens[i];
            UserReward storage userReward = userRewards[_account][rewardToken];
            userReward.rewards = earned(_account, rewardToken);
            userReward.userRewardPerTokenPaid = rewards[rewardToken]
                .rewardPerTokenStored;
        }

        _;
    }

    function earned(
        address _account,
        address _rewardToken
    ) public view returns (uint256) {
        Reward memory reward = rewards[_rewardToken];
        UserReward memory userReward = userRewards[_account][_rewardToken];
        return
            ((balanceOf(_account) *
                (reward.rewardPerTokenStored -
                    userReward.userRewardPerTokenPaid)) / 1e18) +
            userReward.rewards;
    }

    function _addRewardToken(address _rewardToken) internal {
        require(_rewardToken != address(0), "invalid _rewardToken!");
        if (isRewardToken[_rewardToken]) {
            return;
        }
        rewardTokens.push(_rewardToken);
        isRewardToken[_rewardToken] = true;

        emit RewardTokenAdded(_rewardToken);
    }

    function _swapWETH2Pendle(
        uint256 _amount
    ) internal returns (uint256 obtainedAmount) {
        if (_amount == 0) {
            return _amount;
        }
        IBalancer.SingleSwap memory singleSwap;
        singleSwap.poolId = balancerPool;
        singleSwap.kind = IBalancer.SwapKind.GIVEN_IN;
        singleSwap.assetIn = IAsset(address(weth));
        singleSwap.assetOut = IAsset(address(pendle));
        singleSwap.amount = _amount;

        IBalancer.FundManagement memory funds;
        funds.sender = address(this);
        funds.fromInternalBalance = false;
        funds.recipient = payable(address(this));
        funds.toInternalBalance = false;

        weth.safeApprove(address(balancer), _amount);
        return balancer.swap(singleSwap, funds, _amount, block.timestamp);
    }

    function inCaseTokensGetStuck(
        address _token
    ) external onlyRole(ADMIN_ROLE) {
        require(_token != address(ependle), "!token");

        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, amount);
    }

    function setUserHarvest(bool _userHarvest) external onlyRole(ADMIN_ROLE) {
        userHarvest = _userHarvest;
    }

    function setHarvestFeeRate(uint256 _feeRate) external onlyRole(ADMIN_ROLE) {
        require(_feeRate <= (FEE_PRECISION * 30) / 100, "!cap");

        harvestFeeRate = _feeRate;
        emit HarvestFeeRateUpdated(_feeRate);
    }

    function setWithdrawalFeeRate(
        uint256 _feeRate
    ) external onlyRole(ADMIN_ROLE) {
        require(_feeRate <= (FEE_PRECISION * 5) / 100, "!cap");

        withdrawalFeeRate = _feeRate;
        emit WithdrawalFeeRateUpdated(_feeRate);
    }

    function balance() public view returns (uint256) {
        return
            ependle.balanceOf(address(this)) +
            ePendleRewardPool.balanceOf(address(this));
    }

    receive() external payable {}
}
