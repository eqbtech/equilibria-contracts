// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Interfaces/ILybraProxy.sol";
import "./RewardPoolUpg.sol";

contract ELBRRewardPool is RewardPoolUpg {
    ILybraProxy public lybraProxy;

    function initialize(address _eLBR, address _lybraProxy) public initializer {
        __RewardPool_init(_eLBR);
        lybraProxy = ILybraProxy(_lybraProxy);
    }

    function _beforeUpdateReward(address) internal override {
        harvest();
    }

    function harvest() public {
        lybraProxy.getProtocolRewards();
    }
}
