// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./IPendleProxy.sol";

interface IPendleProxyMainchain is IPendleProxy {
    function lockPendle(uint128 _expiry) external;

    // --- Events ---
    event DepositorUpdated(address _depositor);
    event PendleLocked(uint128 _additionalAmountToLock, uint128 _newExpiry);
}
