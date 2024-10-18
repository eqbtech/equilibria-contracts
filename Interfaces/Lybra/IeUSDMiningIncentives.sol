// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IeUSDMiningIncentives {
    function ethlbrStakePool() external view returns (address);

    function earned(address user) external view returns (uint256);

    function getReward() external;

    function isOtherEarningsClaimable(
        address user
    ) external view returns (bool);
}
