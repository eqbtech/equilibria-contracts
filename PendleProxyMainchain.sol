// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Interfaces/IPendleProxyMainchain.sol";
import "./Interfaces/Pendle/IPVotingEscrowMainchain.sol";
import "./PendleProxyBaseUpg.sol";

contract PendleProxyMainchain is PendleProxyBaseUpg, IPendleProxyMainchain {
    using SafeERC20 for IERC20;

    address public pendle;

    address public depositor;

    function initialize() public initializer {
        __PendleProxyBaseUpg_init();
    }

    modifier onlyDepositor() {
        require(msg.sender == depositor, "!auth");
        _;
    }

    function setParams(
        address _pendleMarketFactory,
        address _booster,
        address _depositor
    ) external onlyOwner {
        require(_depositor != address(0), "invalid _depositor!");

        _setParams(_pendleMarketFactory, _booster);

        pendle = IPVotingEscrowMainchain(vePendle).pendle();

        depositor = _depositor;

        emit DepositorUpdated(_depositor);
    }

    function lockPendle(uint128 _expiry) external override onlyDepositor {
        uint256 balance = IERC20(pendle).balanceOf(address(this));

        if (balance > 0) {
            IERC20(pendle).safeApprove(vePendle, 0);
            IERC20(pendle).safeApprove(vePendle, balance);
        }

        IPVotingEscrowMainchain(vePendle).increaseLockPosition(
            uint128(balance),
            _expiry
        );

        emit PendleLocked(uint128(balance), _expiry);
    }
}
