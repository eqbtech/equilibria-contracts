// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import "../Dependencies/EqbConstants.sol";

import "../Interfaces/ISmartConvertor.sol";
import "../Interfaces/IEqbConfig.sol";
import "../Interfaces/IEPendleVaultSidechain.sol";

contract PendleCampaigns is AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    address public pendle;

    address public ePendle;

    IEqbConfig public eqbConfig;

    struct Campaign {
        uint256 startTime;
        uint256 endTime;
        uint256 cap;
        bool convert;
        address[] rewardTokens;
        uint256[] rewardMultiplier;
    }

    mapping(uint256 => Campaign) public campaigns;

    mapping(uint256 => mapping(address => uint256)) public balances;
    mapping(uint256 => uint256) public totalBalances;
    mapping(uint256 => bool) public funded;
    mapping(uint256 => mapping(address => bool)) public claimed;

    event CampaignCreated(uint256 _campaignId, Campaign _campaign);
    event CampaignFunded(uint256 _campaignId);
    event Deposited(
        address indexed _user,
        uint256 _campaignId,
        uint256 _amount
    );
    event Claimed(address indexed _user, uint256 _campaignId);
    event AdminWithdrawn(address indexed _admin, uint256 _amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _pendle,
        address _ePendle,
        address _eqbConfig
    ) public initializer {
        __AccessControl_init();

        pendle = _pendle;
        ePendle = _ePendle;
        eqbConfig = IEqbConfig(_eqbConfig);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(EqbConstants.ADMIN_ROLE, msg.sender);
    }

    function createCampaign(
        uint256 _campaignId,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _cap,
        bool _convert,
        address[] memory _rewardTokens,
        uint256[] memory _rewardMultiplier
    ) external onlyRole(EqbConstants.ADMIN_ROLE) {
        require(
            campaigns[_campaignId].startTime == 0,
            "campaign already exists"
        );

        require(_startTime > 0, "invalid _startTime");
        require(_startTime < _endTime, "invalid time range");

        campaigns[_campaignId] = Campaign({
            startTime: _startTime,
            endTime: _endTime,
            cap: _cap,
            convert: _convert,
            rewardTokens: _rewardTokens,
            rewardMultiplier: _rewardMultiplier
        });

        emit CampaignCreated(_campaignId, campaigns[_campaignId]);
    }

    function fundCampaign(
        uint256 _campaignId
    ) external onlyRole(EqbConstants.ADMIN_ROLE) {
        require(!funded[_campaignId], "campaign already funded");
        require(
            campaigns[_campaignId].endTime <= block.timestamp,
            "campaign not ended"
        );
        uint256 totalBalance = totalBalances[_campaignId];
        require(totalBalance > 0, "no balance to fund");

        for (
            uint256 i = 0;
            i < campaigns[_campaignId].rewardTokens.length;
            i++
        ) {
            IERC20(campaigns[_campaignId].rewardTokens[i]).safeTransferFrom(
                msg.sender,
                address(this),
                (totalBalance * campaigns[_campaignId].rewardMultiplier[i]) /
                    1e18
            );
        }

        funded[_campaignId] = true;

        emit CampaignFunded(_campaignId);
    }

    function getCampaign(
        uint256 _campaignId
    ) external view returns (Campaign memory) {
        return campaigns[_campaignId];
    }

    function deposit(uint256 _campaignId, uint256 _amount) external {
        Campaign memory campaign = campaigns[_campaignId];
        require(campaign.startTime > 0, "campaign not exists");
        require(_amount > 0, "invalid _amount");
        require(campaign.startTime <= block.timestamp, "campaign not started");
        require(campaign.endTime >= block.timestamp, "campaign ended");
        require(
            totalBalances[_campaignId] + _amount <= campaign.cap,
            "campaign cap reached"
        );

        IERC20(pendle).safeTransferFrom(msg.sender, address(this), _amount);

        if (campaign.convert) {
            address smartConvertor = eqbConfig.getContract(
                EqbConstants.SMART_CONVERTOR
            );
            if (smartConvertor != address(0)) {
                _approveTokenIfNeeded(pendle, smartConvertor, _amount);
                ISmartConvertor(smartConvertor).depositFor(_amount, msg.sender);
            } else {
                address ePendleVaultSidechain = eqbConfig.getContract(
                    EqbConstants.EPENDLE_VAULT_SIDECHAIN
                );
                _approveTokenIfNeeded(pendle, ePendleVaultSidechain, _amount);
                IEPendleVaultSidechain(ePendleVaultSidechain).convert(
                    pendle,
                    _amount
                );
                IERC20(ePendle).safeTransfer(msg.sender, _amount);
            }
        }

        balances[_campaignId][msg.sender] += _amount;
        totalBalances[_campaignId] += _amount;

        emit Deposited(msg.sender, _campaignId, _amount);
    }

    function claim(uint256 _campaignId) external {
        require(funded[_campaignId], "campaign not funded");
        require(
            !claimed[_campaignId][msg.sender],
            "user already claimed rewards"
        );

        uint256 userBalance = balances[_campaignId][msg.sender];
        require(userBalance > 0, "no balance to claim");

        for (
            uint256 i = 0;
            i < campaigns[_campaignId].rewardTokens.length;
            i++
        ) {
            IERC20(campaigns[_campaignId].rewardTokens[i]).safeTransfer(
                msg.sender,
                (userBalance * campaigns[_campaignId].rewardMultiplier[i]) /
                    1e18
            );
        }

        claimed[_campaignId][msg.sender] = true;

        emit Claimed(msg.sender, _campaignId);
    }

    function adminWithdrawPendle(
        uint256 _amount
    ) external onlyRole(EqbConstants.ADMIN_ROLE) {
        IERC20(pendle).safeTransfer(msg.sender, _amount);
        emit AdminWithdrawn(msg.sender, _amount);
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
