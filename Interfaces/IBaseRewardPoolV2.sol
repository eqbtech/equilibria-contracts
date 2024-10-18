// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./IBaseRewardPool.sol";

interface IBaseRewardPoolV2 is IBaseRewardPool {
    function initialize(address _owner, address _booster) external;

    function setParams(
        uint256 _pid,
        address _stakingToken,
        address _rewardToken,
        address _eqbZap
    ) external;
}
