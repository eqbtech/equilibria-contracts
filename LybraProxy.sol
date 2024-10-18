// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import "./Interfaces/ILybraProxy.sol";
import "./Interfaces/Lybra/ILybraVault.sol";
import "./Interfaces/Lybra/ILybraConfigurator.sol";
import "./Interfaces/Lybra/IProtocolRewardsPool.sol";
import "./Interfaces/Lybra/IesLBRBoost.sol";
import "./Interfaces/Lybra/IeUSDMiningIncentives.sol";
import "./Interfaces/Lybra/IStakingRewardsV2.sol";
import "./Interfaces/IEqbExternalToken.sol";
import "./Interfaces/ILybraBooster.sol";
import "./Interfaces/IRewards.sol";
import "./Dependencies/Errors.sol";

contract LybraProxy is ILybraProxy, AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    ILybraConfigurator public lybraConfigurator;

    address public EUSD;
    address public peUSD;
    address public usdc;

    IERC20 public LBR;
    IERC20 public esLBR;
    IesLBRBoost public esLBRBoost;
    IProtocolRewardsPool public protocolRewardsPool;
    IeUSDMiningIncentives public eUSDMiningIncentives;
    IStakingRewardsV2 public ethlbrStakePool;
    address public ethlbrLp;

    address public eLBR;
    address public booster;
    address public dLPStakePool;
    address public eLBRRewardPool;
    address public treasury;

    uint256 public esLBRLockSettingId;

    uint256 public constant DENOMINATOR = 10000;
    uint256 public lockShare;
    uint256 public treasuryShare;
    uint256 public dLPShare;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __AccessControl_init();

        lockShare = 500;
        treasuryShare = 500;
        dLPShare = 1000;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    function setParams(
        address _lybraConfigurator,
        address _eLBR,
        address _booster,
        address _dLPStakePool,
        address _eLBRRewardPool,
        address _treasury
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        lybraConfigurator = ILybraConfigurator(_lybraConfigurator);

        EUSD = lybraConfigurator.getEUSDAddress();
        peUSD = lybraConfigurator.peUSD();
        usdc = lybraConfigurator.stableToken();

        protocolRewardsPool = IProtocolRewardsPool(
            lybraConfigurator.getProtocolRewardsPool()
        );
        eUSDMiningIncentives = IeUSDMiningIncentives(
            lybraConfigurator.eUSDMiningIncentives()
        );
        ethlbrStakePool = IStakingRewardsV2(
            eUSDMiningIncentives.ethlbrStakePool()
        );
        ethlbrLp = ethlbrStakePool.stakingToken();

        LBR = IERC20(protocolRewardsPool.LBR());
        esLBR = IERC20(protocolRewardsPool.esLBR());
        esLBRBoost = IesLBRBoost(protocolRewardsPool.esLBRBoost());

        eLBR = _eLBR;
        booster = _booster;
        dLPStakePool = _dLPStakePool;
        eLBRRewardPool = _eLBRRewardPool;

        treasury = _treasury;
    }

    function setTreasury(address _treasury) external onlyRole(ADMIN_ROLE) {
        treasury = _treasury;
    }

    function setEsLBRLockSettingId(
        uint256 _esLBRLockSettingId
    ) external onlyRole(ADMIN_ROLE) {
        esLBRLockSettingId = _esLBRLockSettingId;
    }

    function setLockShare(uint256 _lockShare) external onlyRole(ADMIN_ROLE) {
        lockShare = _lockShare;
        _checkShares();
    }

    function setTreasuryShare(
        uint256 _treasuryShare
    ) external onlyRole(ADMIN_ROLE) {
        treasuryShare = _treasuryShare;
        _checkShares();
    }

    function setDLPShare(uint256 _dLPShare) external onlyRole(ADMIN_ROLE) {
        dLPShare = _dLPShare;
        _checkShares();
    }

    modifier onlyValidVault(address _vault) {
        if (!isValidVault(_vault)) {
            revert Errors.InvalidVault(_vault);
        }

        _;
    }

    modifier onlyBooster() {
        require(msg.sender == booster, "!auth");

        _;
    }

    modifier onlyDLPStakePool() {
        require(msg.sender == dLPStakePool, "!auth");

        _;
    }

    function isValidVault(address _vault) public view override returns (bool) {
        return lybraConfigurator.mintVault(_vault);
    }

    function getVaultWeight(address _vault) external view returns (uint256) {
        return lybraConfigurator.getVaultWeight(_vault);
    }

    function depositEtherToVault(
        address _vault,
        uint256 _mintAmount
    )
        external
        payable
        override
        onlyBooster
        onlyValidVault(_vault)
        returns (uint256)
    {
        if (msg.value < 1 ether) {
            revert Errors.InvalidDepositAmount(msg.value);
        }
        uint256 depositedAssetBefore = ILybraVault(_vault).depositedAsset(
            address(this)
        );
        ILybraVault(_vault).depositEtherToMint{value: msg.value}(_mintAmount);
        return
            ILybraVault(_vault).depositedAsset(address(this)) -
            depositedAssetBefore;
    }

    function depositAssetToVault(
        address _vault,
        uint256 _assetAmount,
        uint256 _mintAmount
    ) external override onlyBooster onlyValidVault(_vault) returns (uint256) {
        if (_assetAmount < 1 ether) {
            revert Errors.InvalidDepositAmount(_assetAmount);
        }
        address collateralAsset = ILybraVault(_vault).getAsset();
        IERC20(collateralAsset).safeTransferFrom(
            msg.sender,
            address(this),
            _assetAmount
        );
        _approveTokenIfNeeded(collateralAsset, _vault, _assetAmount);
        ILybraVault(_vault).depositAssetToMint(_assetAmount, _mintAmount);
        return _assetAmount;
    }

    function withdrawFromVault(
        address _vault,
        address _onBehalfOf,
        uint256 _amount
    ) external override onlyBooster onlyValidVault(_vault) returns (uint256) {
        if (_amount == 0) {
            revert Errors.InvalidAmount(_amount);
        }

        // EUSD vault may have withdraw punishment
        address collateralAsset = ILybraVault(_vault).getAsset();
        uint256 balBefore = IERC20(collateralAsset).balanceOf(address(this));
        ILybraVault(_vault).withdraw(address(this), _amount);
        uint256 withdrawAmount = IERC20(collateralAsset).balanceOf(
            address(this)
        ) - balBefore;
        IERC20(collateralAsset).safeTransfer(_onBehalfOf, withdrawAmount);

        return withdrawAmount;
    }

    function borrowFromVault(
        address _vault,
        uint256 _amount
    ) external override onlyValidVault(_vault) {
        if (_amount == 0) {
            revert Errors.InvalidAmount(_amount);
        }
        ILybraVault(_vault).mint(address(this), _amount);
    }

    function repayVault(
        address _vault,
        uint256 _amount
    ) external override onlyValidVault(_vault) {
        if (_amount == 0) {
            revert Errors.InvalidAmount(_amount);
        }
        ILybraVault(_vault).burn(address(this), _amount);
    }

    function lock(uint256 _amount, bool _useLBR) public override {
        if (_useLBR) {
            if (_amount == 0) {
                revert Errors.InvalidAmount(_amount);
            }
            LBR.safeTransferFrom(msg.sender, address(this), _amount);
        }
        esLBRBoost.setLockStatus(esLBRLockSettingId, _amount, _useLBR);
    }

    function stake(uint256 _amount) external override {
        if (_amount == 0) {
            revert Errors.InvalidAmount(_amount);
        }
        LBR.safeTransferFrom(msg.sender, address(this), _amount);
        protocolRewardsPool.stake(_amount);
    }

    function unstake(uint256 _amount) external override {
        if (_amount == 0) {
            revert Errors.InvalidAmount(_amount);
        }
        protocolRewardsPool.unstake(_amount);
    }

    function withdrawLBR(uint256 _amount) external override {
        if (LBR.balanceOf(address(this)) < _amount) {
            protocolRewardsPool.withdraw(address(this));
        }

        LBR.safeTransfer(msg.sender, _amount);
    }

    function getProtocolRewards()
        external
        override
        returns (address[] memory rewardTokens, uint256[] memory rewardAmounts)
    {
        require(
            msg.sender == eLBRRewardPool || hasRole(ADMIN_ROLE, msg.sender),
            "!auth"
        );
        rewardTokens = new address[](2);
        rewardTokens[0] = peUSD;
        rewardTokens[1] = usdc;

        uint256[] memory balBefore = new uint256[](2);
        balBefore[0] = IERC20(peUSD).balanceOf(address(this));
        balBefore[1] = IERC20(usdc).balanceOf(address(this));

        protocolRewardsPool.getReward();

        rewardAmounts = new uint256[](2);
        rewardAmounts[0] =
            IERC20(peUSD).balanceOf(address(this)) -
            balBefore[0];
        rewardAmounts[1] = IERC20(usdc).balanceOf(address(this)) - balBefore[1];

        if (rewardAmounts[0] > 0) {
            _approveTokenIfNeeded(peUSD, eLBRRewardPool, rewardAmounts[0]);
            IRewards(eLBRRewardPool).queueNewRewards(peUSD, rewardAmounts[0]);
        }
        if (rewardAmounts[1] > 0) {
            _approveTokenIfNeeded(usdc, eLBRRewardPool, rewardAmounts[1]);
            IRewards(eLBRRewardPool).queueNewRewards(usdc, rewardAmounts[1]);
        }
    }

    function stakeEthLbrLp(uint256 _amount) external override onlyDLPStakePool {
        IERC20(ethlbrLp).safeTransferFrom(msg.sender, address(this), _amount);
        _approveTokenIfNeeded(ethlbrLp, address(ethlbrStakePool), _amount);
        ethlbrStakePool.stake(_amount);
    }

    function withdrawEthLbrLp(
        uint256 _amount
    ) external override onlyDLPStakePool {
        ethlbrStakePool.withdraw(_amount);
        IERC20(ethlbrLp).safeTransfer(msg.sender, _amount);
    }

    function getEthLbrStakePoolRewards() external override returns (uint256) {
        require(
            msg.sender == dLPStakePool || hasRole(ADMIN_ROLE, msg.sender),
            "!auth"
        );
        uint256 balBefore = esLBR.balanceOf(address(this));
        ethlbrStakePool.getReward();
        uint256 esLBRAmount = esLBR.balanceOf(address(this)) - balBefore;
        IEqbExternalToken(eLBR).mint(address(this), esLBRAmount);
        _approveTokenIfNeeded(eLBR, dLPStakePool, esLBRAmount);
        IRewards(dLPStakePool).queueNewRewards(eLBR, esLBRAmount);
        return esLBRAmount;
    }

    function getEUSDMiningIncentives() external override returns (uint256) {
        require(
            msg.sender == booster || hasRole(ADMIN_ROLE, msg.sender),
            "!auth"
        );
        if (
            eUSDMiningIncentives.earned(address(this)) == 0 ||
            eUSDMiningIncentives.isOtherEarningsClaimable(address(this))
        ) {
            return 0;
        }
        uint256 balBefore = esLBR.balanceOf(address(this));
        eUSDMiningIncentives.getReward();
        uint256 esLBRAmount = esLBR.balanceOf(address(this)) - balBefore;

        uint256 lockAmount = (esLBRAmount * lockShare) / DENOMINATOR;
        lock(lockAmount, false);
        uint256 treasuryAmount = (esLBRAmount * treasuryShare) / DENOMINATOR;
        IEqbExternalToken(eLBR).mint(treasury, treasuryAmount);
        uint256 dLPAmount = (esLBRAmount * dLPShare) / DENOMINATOR;
        uint256 lsdAmount = esLBRAmount -
            lockAmount -
            treasuryAmount -
            dLPAmount;
        IEqbExternalToken(eLBR).mint(address(this), dLPAmount + lsdAmount);
        _approveTokenIfNeeded(eLBR, dLPStakePool, dLPAmount);
        IRewards(dLPStakePool).queueNewRewards(eLBR, dLPAmount);
        _approveTokenIfNeeded(eLBR, booster, lsdAmount);
        ILybraBooster(booster).queueNewRewards(eLBR, lsdAmount);
        return esLBRAmount;
    }

    function _checkShares() internal view {
        require(lockShare + treasuryShare + dLPShare < DENOMINATOR, "!shares");
        require(lockShare >= 500 && lockShare <= 2000, "invalid lockShare");
        require(
            treasuryShare >= 0 && treasuryShare <= 1000,
            "invalid treasuryShare"
        );
        require(dLPShare >= 500 && dLPShare <= 2000, "invalid dLPShare");
        uint256 lsdShare = DENOMINATOR - lockShare - treasuryShare - dLPShare;
        require(lsdShare >= 5000 && lsdShare <= 9000, "invalid lsdShare");
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
