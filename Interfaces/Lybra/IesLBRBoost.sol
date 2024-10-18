// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IesLBRBoost {
    /**
     * @notice The user can set the lock status and choose to use either esLBR or LBR.
     * @param id The ID of the lock setting.
     * @param lbrAmount The amount of LBR to be locked.
     * @param useLBR A flag indicating whether to use LBR or not.
     */
    function setLockStatus(uint256 id, uint256 lbrAmount, bool useLBR) external;
}
