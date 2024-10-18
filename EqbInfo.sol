// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import "./Interfaces/IBaseRewardPool.sol";
import "./Interfaces/IPendleBooster.sol";
import "./Interfaces/IEqbConfig.sol";

import "./Dependencies/EqbConstants.sol";

contract EqbInfo is AccessControlUpgradeable {
    IPendleBooster public booster;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _booster) public initializer {
        require(_booster != address(0), "invalid _booster!");
        __AccessControl_init();

        booster = IPendleBooster(_booster);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function getLpDeposited(
        address _market,
        address _user
    ) external view returns (uint256) {
        uint256 poolLength = booster.poolLength();
        for (uint256 pid = 0; pid < poolLength; pid++) {
            (address market, , address rewardPool, bool shutdown) = booster
                .poolInfo(pid);
            if (market == _market && !shutdown) {
                return IBaseRewardPool(rewardPool).balanceOf(_user);
            }
        }
        return 0;
    }
}
