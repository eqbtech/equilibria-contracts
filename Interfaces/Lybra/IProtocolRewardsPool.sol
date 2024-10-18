// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IProtocolRewardsPool {
    function LBR() external view returns (address);

    function esLBR() external view returns (address);

    function esLBRBoost() external view returns (address);

    function stake(uint256 amount) external;

    /**
     * @dev Unlocks esLBR and converts it to LBR.
     * @param amount The amount to convert.
     * Requirements:
     * If the current time is less than the unlock time of the user's lock status in the esLBRBoost contract,
     * the locked portion in the esLBRBoost contract cannot be unlocked.
     * Effects:
     * Resets the user's vesting data, entering a new vesting period, when converting to LBR.
     */
    function unstake(uint256 amount) external;

    function withdraw(address user) external;

    function getReward() external;
}
