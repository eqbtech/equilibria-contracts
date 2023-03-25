// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

library WeekMath {
    uint128 internal constant WEEK = 7 days;

    function getWeekStartTimestamp(
        uint128 timestamp
    ) internal pure returns (uint128) {
        return (timestamp / WEEK) * WEEK;
    }

    function getCurrentWeekStart() internal view returns (uint128) {
        return getWeekStartTimestamp(uint128(block.timestamp));
    }

    function isValidWTime(uint256 time) internal pure returns (bool) {
        return time % WEEK == 0;
    }
}
