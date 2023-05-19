// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract FairAuction is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using Address for address;

    address public PROJECT_TOKEN; // Project token contract
    address public SALE_TOKEN; // token used to participate

    uint256 public START_TIME; // sale start time
    uint256 public END_TIME; // sale end time

    uint256 public MAX_PROJECT_TOKENS_TO_DISTRIBUTE; // max PROJECT_TOKEN amount to distribute during the sale
    uint256 public MIN_TOTAL_RAISED_FOR_MAX_PROJECT_TOKEN; // amount to reach to distribute max PROJECT_TOKEN amount

    uint256 public MAX_RAISE_AMOUNT;
    uint256 public CAP_PER_WALLET;

    address public treasury; // treasury multisig, will receive raised amount

    struct UserInfo {
        uint256 contribution; // amount spent to buy TOKEN
        bool whitelisted;
        uint256 whitelistCap;
        uint256 claimedAmount;
    }

    mapping(address => UserInfo) public userInfo; // buyers info
    uint256 public totalRaised; // raised amount

    uint256 public constant PRECISION = 1e4;
    // initial unlock percentage
    uint256 public unlockPercent;
    // linear release duration in second
    uint256 public releaseDuration;

    bool public whitelistOnly;

    function initialize(
        address _projectToken,
        address _saleToken,
        uint256 _startTime,
        uint256 _endTime,
        address _treasury,
        uint256 _maxToDistribute,
        uint256 _minToRaise,
        uint256 _maxToRaise,
        uint256 _capPerWallet
    ) public initializer {
        require(_projectToken != address(0), "invalid _projectToken");
        require(_saleToken != address(0), "invalid _saleToken");
        require(_startTime > _currentBlockTimestamp(), "invalid _startTime");
        require(_startTime < _endTime, "invalid dates");
        require(_treasury != address(0), "invalid _treasury");

        __Ownable_init();

        __ReentrancyGuard_init_unchained();

        PROJECT_TOKEN = _projectToken;
        SALE_TOKEN = _saleToken;
        START_TIME = _startTime;
        END_TIME = _endTime;
        treasury = _treasury;
        MAX_PROJECT_TOKENS_TO_DISTRIBUTE = _maxToDistribute;
        MIN_TOTAL_RAISED_FOR_MAX_PROJECT_TOKEN = _minToRaise;
        if (_maxToRaise == 0) {
            _maxToRaise = type(uint256).max;
        }
        MAX_RAISE_AMOUNT = _maxToRaise;
        if (_capPerWallet == 0) {
            _capPerWallet = type(uint256).max;
        }
        CAP_PER_WALLET = _capPerWallet;

        unlockPercent = 5000;
        releaseDuration = 180 days;

        whitelistOnly = true;
    }

    /********************************************/
    /****************** EVENTS ******************/
    /********************************************/

    event Buy(address indexed _user, uint256 _amount);
    event Claim(address indexed _user, uint256 _amount);
    event WhitelistUpdated(WhitelistSettings[] settings);
    event SetWhitelistOnly(bool _whitelistOnly);

    /***********************************************/
    /****************** MODIFIERS ******************/
    /***********************************************/

    /**
     * @dev Check whether the sale is currently active
     *
     * Will be marked as inactive if PROJECT_TOKEN has not been deposited into the contract
     */
    modifier isSaleActive() {
        require(hasStarted() && !hasEnded(), "isActive: sale is not active");
        _;
    }

    /**
     * @dev Check whether users can claim their purchased PROJECT_TOKEN
     *
     * Sale must have ended
     */
    modifier isClaimable() {
        require(hasEnded(), "isClaimable: sale has not ended");
        require(
            IERC20(PROJECT_TOKEN).balanceOf(address(this)) > 0,
            "isClaimable: sale not filled"
        );
        _;
    }

    /**************************************************/
    /****************** PUBLIC VIEWS ******************/
    /**************************************************/

    /**
     * @dev Get remaining duration before the end of the sale
     */
    function getRemainingTime() external view returns (uint256) {
        if (hasEnded()) return 0;
        return END_TIME - _currentBlockTimestamp();
    }

    /**
     * @dev Returns whether the sale has already started
     */
    function hasStarted() public view returns (bool) {
        return _currentBlockTimestamp() >= START_TIME;
    }

    /**
     * @dev Returns whether the sale has already ended
     */
    function hasEnded() public view returns (bool) {
        return END_TIME <= _currentBlockTimestamp();
    }

    /**
     * @dev Returns the amount of PROJECT_TOKEN to be distributed based on the current total raised
     */
    function projectTokensToDistribute() public view returns (uint256) {
        if (MIN_TOTAL_RAISED_FOR_MAX_PROJECT_TOKEN > totalRaised) {
            return
                (MAX_PROJECT_TOKENS_TO_DISTRIBUTE * totalRaised) /
                MIN_TOTAL_RAISED_FOR_MAX_PROJECT_TOKEN;
        }
        return MAX_PROJECT_TOKENS_TO_DISTRIBUTE;
    }

    /**
     * @dev Get user claim amounts
     */
    function getClaimAmounts(
        address _user
    )
        public
        view
        returns (
            uint256 totalAmount,
            uint256 claimedAmount,
            uint256 claimableAmount
        )
    {
        if (totalRaised == 0) {
            return (0, 0, 0);
        }

        UserInfo memory user = userInfo[_user];
        if (user.contribution == 0) {
            return (0, 0, 0);
        }

        totalAmount =
            (user.contribution * projectTokensToDistribute()) /
            totalRaised;
        claimedAmount = user.claimedAmount;

        if (!hasEnded()) {
            claimableAmount = 0;
        } else {
            // initial unlock
            uint256 unlockAmount = (totalAmount * unlockPercent) / PRECISION;
            // linear release
            uint256 lockedAmount = totalAmount - unlockAmount;
            uint256 timePassed = _currentBlockTimestamp() - END_TIME;
            uint256 releasedAmount = 0;
            if (timePassed >= releaseDuration) {
                releasedAmount = lockedAmount;
            } else {
                releasedAmount = (lockedAmount * timePassed) / releaseDuration;
            }
            claimableAmount = unlockAmount + releasedAmount - claimedAmount;
        }
    }

    /****************************************************************/
    /****************** EXTERNAL PUBLIC FUNCTIONS  ******************/
    /****************************************************************/

    /**
     * @dev Purchase an allocation for the sale for a value of "amount" SALE_TOKEN
     */
    function buy(uint256 _amount) external isSaleActive nonReentrant {
        require(_amount > 0, "buy: zero amount");
        require(
            totalRaised + _amount <= MAX_RAISE_AMOUNT,
            "buy: hardcap reached"
        );
        require(msg.sender == tx.origin, "FORBIDDEN");

        UserInfo storage user = userInfo[msg.sender];

        if (whitelistOnly) {
            require(user.whitelisted, "buy: not whitelisted");
            require(
                user.contribution + _amount <= user.whitelistCap,
                "buy: whitelist wallet cap reached"
            );
        } else {
            uint256 userWalletCap = CAP_PER_WALLET > user.whitelistCap
                ? CAP_PER_WALLET
                : user.whitelistCap;
            require(
                user.contribution + _amount <= userWalletCap,
                "buy: wallet cap reached"
            );
        }

        // transfer contribution to treasury
        IERC20(SALE_TOKEN).safeTransferFrom(msg.sender, treasury, _amount);

        // update raised amounts
        user.contribution += _amount;
        totalRaised += _amount;

        emit Buy(msg.sender, _amount);
    }

    /**
     * @dev Claim purchased PROJECT_TOKEN during the sale
     */
    function claim() external isClaimable {
        (, , uint256 claimableAmount) = getClaimAmounts(msg.sender);
        require(claimableAmount > 0, "claim: nothing to claim");

        userInfo[msg.sender].claimedAmount += claimableAmount;

        IERC20(PROJECT_TOKEN).safeTransfer(msg.sender, claimableAmount);

        emit Claim(msg.sender, claimableAmount);
    }

    /****************************************************************/
    /********************** OWNABLE FUNCTIONS  **********************/
    /****************************************************************/

    struct WhitelistSettings {
        address user;
        bool whitelisted;
        uint256 whitelistCap;
    }

    /**
     * @dev Assign whitelist status and cap for users
     */
    function setUsersWhitelist(
        WhitelistSettings[] calldata _settings
    ) public onlyOwner {
        for (uint256 i = 0; i < _settings.length; ++i) {
            WhitelistSettings memory userWhitelist = _settings[i];
            UserInfo storage user = userInfo[userWhitelist.user];
            user.whitelisted = userWhitelist.whitelisted;
            user.whitelistCap = userWhitelist.whitelistCap;
        }

        emit WhitelistUpdated(_settings);
    }

    function setWhitelistOnly(bool _whitelistOnly) external onlyOwner {
        whitelistOnly = _whitelistOnly;
        emit SetWhitelistOnly(_whitelistOnly);
    }

    function setReleaseDuration(uint256 _releaseDuration) external onlyOwner {
        require(!hasEnded(), "setReleaseDuration: sale has ended");
        releaseDuration = _releaseDuration;
    }

    /**
     * @dev Utility function to get the current block timestamp
     */
    function _currentBlockTimestamp() internal view virtual returns (uint256) {
        return block.timestamp;
    }
}
