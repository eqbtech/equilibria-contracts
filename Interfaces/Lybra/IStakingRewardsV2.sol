// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IStakingRewardsV2 {
    function stakingToken() external view returns (address);

    function stake(uint256 _amount) external;

    function withdraw(uint256 _amount) external;

    function getReward() external;
}
