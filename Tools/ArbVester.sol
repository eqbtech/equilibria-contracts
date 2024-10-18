// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@shared/lib-contracts-v0.8/contracts/Dependencies/TransferHelper.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "../Dependencies/EqbConstants.sol";
import "../Interfaces/Arb/IArbVester.sol";
import "../Interfaces/IERC20MintBurn.sol";
import "../Interfaces/Camelot/ICamelotPair.sol";
import "../Interfaces/Camelot/INitroPool.sol";
import "../Interfaces/Camelot/INFTPool.sol";
import "../Interfaces/IOracle.sol";

contract ArbVester is
    IArbVester,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public constant WEEK = 86400 * 7;
    uint256 public constant MIN_WEEK = 1;
    uint256 public constant MAX_WEEK = 40;
    uint256 public expireWeeks;

    address public arb;
    address public oArb;
    address public lp;
    address public usdt;
    IOracle public oracle;

    address public nitroPool;
    address public nftPool;
    uint256 public nftTokenId;

    uint256 public discountPerWeek;
    uint256 public constant DISCOUNT_PRECISION = 1e3;
    uint256 public constant PRECISION = 1e18;
    uint256 public constant LP_DECIMALS = 1e18;

    // all vesting positions
    VestingPosition[] public vestingPositions;
    // user address => vesting position ids
    mapping(address => uint256[]) public userVestingPositions;
    // total lp amount
    uint256 public totalLpAmount;
    // asset => rewardPerShare
    mapping(address => uint256) public rewardPerShare;
    // vestId => asset => currentRewardPerShare
    mapping(uint256 => mapping(address => Reward)) public rewardByVestId;
    // reward tokens
    EnumerableSet.AddressSet private rewardTokens;
    EnumerableSet.AddressSet private nftRewardTokens;
    // vestNft or not for vestId
    mapping(uint256 => bool) public vestInNft;
    // unlock time in advance for vestId
    mapping(uint256 => uint256) public unlockTimeInAdvance;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _arb,
        address _oArb,
        address _lp,
        address _ePendle,
        address _usdt,
        address _oracle,
        address _nitroPool
    ) public initializer {
        __AccessControl_init();

        require(_arb != address(0), "Vester: invalid _arb");
        require(_oArb != address(0), "Vester: invalid _oArb");
        require(_lp != address(0), "Vester: invalid _lp");
        require(_usdt != address(0), "Vester: invalid _usdt");
        require(_oracle != address(0), "Vester: invalid _oracle");
        require(_nitroPool != address(0), "Vester: invalid _nitroPool");
        arb = _arb;
        oArb = _oArb;
        lp = _lp;
        address _token0 = ICamelotPair(lp).token0();
        address _token1 = ICamelotPair(lp).token1();
        require(_token0 == _ePendle || _token1 == _arb, "Vester: invalid _lp");
        usdt = _usdt;
        oracle = IOracle(_oracle);
        nitroPool = _nitroPool;
        nftPool = INitroPool(_nitroPool).nftPool();

        (address _rewardToken1, , , ) = INitroPool(_nitroPool).rewardsToken1();
        (address _rewardToken2, , , ) = INitroPool(_nitroPool).rewardsToken2();
        rewardTokens.add(_rewardToken1);
        rewardTokens.add(_rewardToken2);

        (, address _grailToken, address _xGrailToken, , , , , ) = INFTPool(
            nftPool
        ).getPoolInfo();
        nftRewardTokens.add(_grailToken);
        nftRewardTokens.add(_xGrailToken);

        expireWeeks = 4;
        discountPerWeek = 25;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(EqbConstants.ADMIN_ROLE, msg.sender);
    }

    function adminAddArb(
        uint256 _amount
    ) external onlyRole(EqbConstants.ADMIN_ROLE) {
        require(_amount > 0, "Vester: invalid _amount");
        IERC20(arb).safeTransferFrom(msg.sender, address(this), _amount);
        IERC20MintBurn(oArb).mint(msg.sender, _amount);
        emit ArbAdded(msg.sender, _amount);
    }

    function adminWithdraw(
        uint256 _amount
    ) external onlyRole(EqbConstants.ADMIN_ROLE) {
        require(
            _amount <= IERC20(arb).balanceOf(address(this)),
            "Vester: amount exceeds balance"
        );
        uint256 _usdtBalance = IERC20(usdt).balanceOf(address(this));
        if (_usdtBalance > 0) {
            IERC20(usdt).safeTransfer(msg.sender, _usdtBalance);
        }
        if (_amount > 0) {
            IERC20(arb).safeTransfer(msg.sender, _amount);
        }
        emit Withdrawn(msg.sender, _usdtBalance, _amount);
    }

    function vestNft(
        uint256 _amount,
        uint256 _weeks,
        uint256 _nftTokenId
    ) external override updateReward {
        _requireVestParams(_amount, _weeks);
        require(
            IERC721(nftPool).ownerOf(_nftTokenId) == msg.sender,
            "Vester: invalid nft owner"
        );

        IERC20(oArb).safeTransferFrom(msg.sender, address(this), _amount);
        (uint256 _lpAmount, , , , , , , ) = INFTPool(nftPool)
            .getStakingPosition(_nftTokenId);
        uint256 _calculatedLpAmount = _calculateLpAmount(_amount);
        require(
            _lpAmount >= _calculatedLpAmount,
            "Vester: _lpAmount locked in the nft not enough"
        );
        IERC721(nftPool).safeTransferFrom(
            msg.sender,
            address(this),
            _nftTokenId
        );
        IERC721(nftPool).safeTransferFrom(
            address(this),
            nitroPool,
            _nftTokenId
        );

        _vest(nftTokenId, _amount, _lpAmount, _weeks, true);
    }

    function vest(
        uint256 _amount,
        uint256 _weeks
    ) external override updateReward {
        _requireVestParams(_amount, _weeks);

        IERC20(oArb).safeTransferFrom(msg.sender, address(this), _amount);
        uint256 _lpAmount = _calculateLpAmount(_amount);
        IERC20(lp).safeTransferFrom(msg.sender, address(this), _lpAmount);

        _createNftPosition(_lpAmount, _weeks);
        IERC721(nftPool).safeTransferFrom(address(this), nitroPool, nftTokenId);

        _vest(nftTokenId, _amount, _lpAmount, _weeks, false);
    }

    function _requireVestParams(uint256 _amount, uint256 _weeks) internal pure {
        require(_amount > 0, "Vester: invalid _amount");
        require(
            _weeks >= MIN_WEEK && _weeks <= MAX_WEEK,
            "Vester: invalid _weeks"
        );
    }

    function _vest(
        uint256 _nftTokenId,
        uint256 _amount,
        uint256 _lpAmount,
        uint256 _weeks,
        bool _vestInNft
    ) internal {
        uint256 _vestId = vestingPositions.length;
        vestingPositions.push(
            VestingPosition({
                user: msg.sender,
                amount: _amount,
                lpAmount: _lpAmount,
                nftTokenId: _nftTokenId,
                start: block.timestamp,
                durationWeeks: _weeks,
                closed: false,
                unlocked: false
            })
        );
        userVestingPositions[msg.sender].push(_vestId);

        if (_vestInNft) {
            vestInNft[_vestId] = true;
        }

        // init vestId reward
        for (uint256 i = 0; i < rewardTokens.length(); i++) {
            address _rewardToken = rewardTokens.at(i);
            rewardByVestId[_vestId][_rewardToken] = Reward({
                claimedAmount: 0,
                rewardPerShare: rewardPerShare[_rewardToken],
                pendingAmount: 0
            });
        }

        // update total lp amount
        _updateTotalLpAmount(true, _lpAmount);

        emit VestingPositionAdded(
            msg.sender,
            _amount,
            _lpAmount,
            _weeks,
            block.timestamp,
            _vestId,
            _vestInNft
        );
    }

    function closeVestingPosition(
        uint256 _vestId,
        uint256 _maxAmount
    ) external {
        require(_vestId < vestingPositions.length, "Vester: invalid _vestId");

        VestingPosition storage vestingPosition = vestingPositions[_vestId];
        require(vestingPosition.user == msg.sender, "Vester: invalid user");
        (
            uint256 _unlockTime,
            uint256 _expireTime,
            uint256 _durationWeeks
        ) = _vestingPositionInfo(_vestId, vestingPosition);

        require(
            _unlockTime < block.timestamp,
            "Vester: vesting position not matured"
        );
        require(
            _expireTime > block.timestamp,
            "Vester: vesting position has expired"
        );
        require(
            !vestingPosition.closed,
            "Vester: vesting position already closed"
        );

        uint256 _usdtAmount = _calculateVestingAmount(
            vestingPosition.amount,
            _durationWeeks
        );
        require(_usdtAmount <= _maxAmount, "Vester: amount exceeds _maxAmount");
        // close the vesting position
        vestingPosition.closed = true;

        uint256 _amount = vestingPosition.amount;
        IERC20(usdt).safeTransferFrom(
            vestingPosition.user,
            address(this),
            _usdtAmount
        );
        IERC20MintBurn(oArb).burn(address(this), _amount);
        // user buy the ARB
        IERC20(arb).safeTransfer(vestingPosition.user, _amount);

        emit VestingPositionClosed(msg.sender, _amount, _vestId, _usdtAmount);
    }

    function _vestingPositionInfo(
        uint256 _vestId,
        VestingPosition memory _vestingPosition
    )
        internal
        view
        returns (
            uint256 _unlockTime,
            uint256 _expireTime,
            uint256 _durationWeeks
        )
    {
        if (unlockTimeInAdvance[_vestId] > 0) {
            _unlockTime = unlockTimeInAdvance[_vestId];
            _durationWeeks = (_unlockTime - _vestingPosition.start) / WEEK;
        } else {
            _unlockTime = _getTimeWeeksAfter(
                _vestingPosition.start,
                _vestingPosition.durationWeeks
            );
            _durationWeeks = _vestingPosition.durationWeeks;
        }
        _expireTime = _getTimeWeeksAfter(_unlockTime, expireWeeks);
    }

    // the lp deposit to the nitro pool

    function _createNftPosition(
        uint256 _lpAmount,
        uint256 _durationWeeks
    ) internal {
        // onERC721Received will be called when the NFT is transferred to this contract
        IERC20(lp).approve(nftPool, _lpAmount);
        INFTPool(nftPool).createPosition(_lpAmount, _durationWeeks * WEEK);
    }

    function _withdrawNftPosition(
        VestingPosition memory _vestingPosition
    ) internal {
        INFTPool(nftPool).withdrawFromPosition(
            _vestingPosition.nftTokenId,
            _vestingPosition.lpAmount
        );
        IERC20(lp).safeTransfer(
            _vestingPosition.user,
            _vestingPosition.lpAmount
        );
    }

    function calculateLpAmount(
        uint256 _arbAmount
    ) external view returns (uint256) {
        return _calculateLpAmount(_arbAmount);
    }

    function _calculateLpAmount(
        uint256 _arbAmount
    ) internal view returns (uint256) {
        uint256 _lpTotalSupply = IERC20(lp).totalSupply();
        uint256 _lpReserveArb = IERC20(arb).balanceOf(lp);
        require(_lpReserveArb > 0, "Vester: invalid lp reserve arb");
        return (_arbAmount * _lpTotalSupply) / _lpReserveArb / 2;
    }

    function _updateTotalLpAmount(bool _income, uint256 _lpAmount) internal {
        if (_lpAmount == 0) {
            return;
        }
        if (_income) {
            totalLpAmount += _lpAmount;
        } else {
            totalLpAmount -= _lpAmount;
        }
        emit TotalLpChanged(totalLpAmount, _income, _lpAmount);
    }

    // the nftPool withdraw lp will callback this function
    function onNFTWithdraw(
        address /*operator*/,
        uint256 /*tokenId*/,
        uint256 /*amount*/
    ) external pure returns (bool) {
        return true;
    }

    function onERC721Received(
        address /*operator*/,
        address,
        uint256 tokenId,
        bytes calldata /*data*/
    ) external nonReentrant returns (bytes4) {
        require(
            msg.sender == nftPool || msg.sender == nitroPool,
            "Vester: invalid caller"
        );
        // from nftPool is create the position
        if (msg.sender == nftPool) {
            nftTokenId = tokenId;
        }
        return this.onERC721Received.selector;
    }

    function unlock(uint256 _vestId) external updateReward {
        _requireUnlock(_vestId, true);
        _unlock(_vestId);
    }

    function _requireUnlock(uint256 _vestId, bool _requireMatured) internal view {
        require(_vestId < vestingPositions.length, "Vester: invalid _vestId");

        VestingPosition memory vestingPosition = vestingPositions[_vestId];
        require(vestingPosition.user == msg.sender, "Vester: invalid user");
        uint256 _unlockTime = _getTimeWeeksAfter(
            vestingPosition.start,
            vestingPosition.durationWeeks
        );
        if (_requireMatured) {
            require(
                _unlockTime < block.timestamp,
                "Vester: vesting position not matured"
            );
        } else {
            require(
                _unlockTime >= block.timestamp,
                "Vester: vesting position matured"
            );
        }
        require(
            !vestingPosition.unlocked,
            "Vester: vesting position already unlocked"
        );
    }

    function unlockInAdvance(uint256 _vestId) external {
        _requireUnlock(_vestId, false);
        _unlock(_vestId);
        // set the unlock in advance flag
        unlockTimeInAdvance[_vestId] = block.timestamp;
        emit UnlockInAdvance(_vestId);
    }

    function _unlock(uint256 _vestId) internal updateReward {
        VestingPosition storage vestingPosition = vestingPositions[_vestId];
        _updateNftPoolReward(_vestId);

        // claim reward
        _claimReward(_vestId);

        // unlock vesting position
        vestingPosition.unlocked = true;

        // withdraw nftToken
        INitroPool(nitroPool).withdraw(vestingPosition.nftTokenId);

        if (vestInNft[_vestId]) {
            // user get back the nft
            IERC721(nftPool).safeTransferFrom(
                address(this),
                vestingPosition.user,
                vestingPosition.nftTokenId
            );
        } else {
            // user get back the locked lp
            _withdrawNftPosition(vestingPosition);
        }

        // update total lp amount
        uint256 _lpAmount = vestingPosition.lpAmount;
        _updateTotalLpAmount(false, _lpAmount);

        emit VestingPositionUnlocked(
            vestingPosition.user,
            _lpAmount,
            _vestId,
            vestInNft[_vestId]
        );
    }

    function getRewardTokens() external view returns (address[] memory) {
        address[] memory _rewardTokens = new address[](
            rewardTokens.length() + nftRewardTokens.length()
        );
        for (uint256 i = 0; i < rewardTokens.length(); i++) {
            _rewardTokens[i] = rewardTokens.at(i);
        }
        for (uint256 i = 0; i < nftRewardTokens.length(); i++) {
            _rewardTokens[i + rewardTokens.length()] = nftRewardTokens.at(i);
        }
        return _rewardTokens;
    }

    function getPendingRewards(
        uint256 _vestId
    ) external view returns (uint256[] memory) {
        require(_vestId < vestingPositions.length, "Vester: invalid _vestId");

        VestingPosition memory _vestingPosition = vestingPositions[_vestId];
        uint256[] memory _pendingRewards = new uint256[](
            nftRewardTokens.length() + rewardTokens.length()
        );
        for (uint256 i = 0; i < rewardTokens.length(); i++) {
            address _rewardToken = rewardTokens.at(i);
            Reward memory _reward = rewardByVestId[_vestId][_rewardToken];
            _pendingRewards[i] =
                ((rewardPerShare[_rewardToken] - _reward.rewardPerShare) *
                    _vestingPosition.lpAmount) /
                LP_DECIMALS;
        }
        for (uint256 i = 0; i < nftRewardTokens.length(); i++) {
            _pendingRewards[i + rewardTokens.length()] =
                INFTPool(nftPool).pendingRewards(_vestingPosition.nftTokenId) /
                2;
        }
        return _pendingRewards;
    }

    function claimRewards(uint256 _vestId) external updateReward {
        require(_vestId < vestingPositions.length, "Vester: invalid _vestId");
        VestingPosition memory _vestingPosition = vestingPositions[_vestId];
        require(_vestingPosition.user == msg.sender, "Vester: invalid user");
        require(
            !_vestingPosition.unlocked,
            "Vester: vesting position already unlocked"
        );

        _updateNftPoolReward(_vestId);
        _claimReward(_vestId);
    }

    function _claimReward(uint256 _vestId) internal {
        VestingPosition memory _vestingPosition = vestingPositions[_vestId];
        // nitroPool rewards
        for (uint256 i = 0; i < rewardTokens.length(); i++) {
            address _rewardToken = rewardTokens.at(i);
            Reward storage _reward = rewardByVestId[_vestId][_rewardToken];
            uint256 _rewardAmount = ((rewardPerShare[_rewardToken] -
                _reward.rewardPerShare) * _vestingPosition.lpAmount) /
                LP_DECIMALS;
            // the nitroPool reward
            if (_rewardAmount > 0) {
                _reward.claimedAmount += _rewardAmount;
                _reward.rewardPerShare = rewardPerShare[_rewardToken];
                IERC20(_rewardToken).safeTransfer(
                    _vestingPosition.user,
                    _rewardAmount
                );
                emit ClaimedReward(
                    _vestingPosition.user,
                    _rewardToken,
                    _rewardAmount,
                    _reward.claimedAmount
                );
            }
        }
        // nftPool rewards
        for (uint256 i = 0; i < nftRewardTokens.length(); i++) {
            address _rewardToken = nftRewardTokens.at(i);
            Reward storage _reward = rewardByVestId[_vestId][_rewardToken];
            uint256 _rewardAmount = _reward.pendingAmount;
            if (_rewardAmount > 0) {
                _reward.claimedAmount += _rewardAmount;
                _reward.pendingAmount = 0;
                IERC20(_rewardToken).safeTransfer(
                    _vestingPosition.user,
                    _rewardAmount
                );
                emit ClaimedReward(
                    _vestingPosition.user,
                    _rewardToken,
                    _rewardAmount,
                    _reward.claimedAmount
                );
            }
        }
    }

    function calculateVestingAmount(
        uint256 _amount,
        uint256 _weeks
    ) external view returns (uint256) {
        return _calculateVestingAmount(_amount, _weeks);
    }

    function _calculateVestingAmount(
        uint256 _amount,
        uint256 _weeks
    ) internal view returns (uint256) {
        uint256 discount = _weeks * discountPerWeek;
        uint256 _usdtAmount = (_amount *
            oracle.getPrice() *
            (DISCOUNT_PRECISION - discount)) /
            DISCOUNT_PRECISION /
            PRECISION;
        return
            _decimalConvert(
                _usdtAmount,
                ERC20(oArb).decimals(),
                ERC20(usdt).decimals()
            );
    }

    function _decimalConvert(
        uint256 _amount,
        uint8 _from,
        uint8 _to
    ) internal pure returns (uint256) {
        return (_amount * 10 ** _to) / 10 ** _from;
    }

    function getVestingPosition(
        uint256 _vestId
    ) external view returns (VestingPosition memory) {
        return vestingPositions[_vestId];
    }

    function getUserVestingPositions(
        address _user
    ) external view override returns (uint256[] memory) {
        return userVestingPositions[_user];
    }

    function _getTimeWeeksAfter(
        uint256 _start,
        uint256 _weeks
    ) internal pure returns (uint256) {
        return _start + _weeks * WEEK;
    }

    modifier updateReward() {
        if (totalLpAmount == 0) {
            _;
            return;
        }
        uint256[] memory _balanceBefore = new uint256[](rewardTokens.length());
        for (uint256 i = 0; i < rewardTokens.length(); i++) {
            address _rewardToken = rewardTokens.at(i);
            _balanceBefore[i] = IERC20(_rewardToken).balanceOf(address(this));
        }
        INitroPool(nitroPool).harvest();
        for (uint256 i = 0; i < rewardTokens.length(); i++) {
            address _rewardToken = rewardTokens.at(i);
            uint256 _reward = IERC20(_rewardToken).balanceOf(address(this)) -
                _balanceBefore[i];
            rewardPerShare[_rewardToken] =
                rewardPerShare[_rewardToken] +
                (_reward * LP_DECIMALS) /
                totalLpAmount;
        }
        _;
    }

    function _updateNftPoolReward(uint256 _vestId) internal {
        VestingPosition memory _vestingPosition = vestingPositions[_vestId];
        uint256[] memory _balanceBefore = new uint256[](
            nftRewardTokens.length()
        );
        for (uint256 i = 0; i < nftRewardTokens.length(); i++) {
            address _rewardToken = nftRewardTokens.at(i);
            _balanceBefore[i] = IERC20(_rewardToken).balanceOf(address(this));
        }
        INFTPool(nftPool).harvestPosition(_vestingPosition.nftTokenId);
        for (uint256 i = 0; i < nftRewardTokens.length(); i++) {
            address _rewardToken = nftRewardTokens.at(i);
            uint256 _reward = IERC20(_rewardToken).balanceOf(address(this)) -
                _balanceBefore[i];
            rewardByVestId[_vestId][_rewardToken].pendingAmount += _reward;
        }
    }

    receive() external payable {}
}
