// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Interfaces/ILybraProxy.sol";
import "./RewardPoolUpg.sol";

contract LybraDLPStakePool is RewardPoolUpg {
    using SafeERC20 for IERC20;

    ILybraProxy public lybraProxy;
    address public eLBR;

    function initialize(
        address _ethlbrLp,
        address _lybraProxy,
        address _eLBR
    ) public initializer {
        __RewardPool_init(_ethlbrLp);
        lybraProxy = ILybraProxy(_lybraProxy);
        eLBR = _eLBR;

        _addRewardToken(_eLBR);

        stakingToken.safeApprove(_lybraProxy, type(uint256).max);
    }

    function _stake(address, uint256 _amount) internal override {
        lybraProxy.stakeEthLbrLp(_amount);
    }

    function _withdraw(address, uint256 _amount) internal override {
        lybraProxy.withdrawEthLbrLp(_amount);
    }

    function _beforeUpdateReward(address) internal override {
        harvest();
    }

    function harvest() public {
        lybraProxy.getEthLbrStakePoolRewards();
    }
}
