// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./PendleBoosterBaseUpg.sol";

contract PendleBoosterSidechain is PendleBoosterBaseUpg {
    using TransferHelper for address;
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet internal allowedRewardContracts;

    function initialize() public initializer {
        __PendleBoosterBaseUpg_init();
    }

    function getAllowedRewardContracts()
        external
        view
        returns (address[] memory)
    {
        return allowedRewardContracts.values();
    }

    function addAllowedRewardContract(
        address _rewardContract
    ) external onlyOwner {
        require(_rewardContract != address(0), "invalid _rewardContract");
        allowedRewardContracts.add(_rewardContract);
    }

    function _isAllowedRewardContract(
        address _rewardContract,
        PoolInfo memory _pool
    ) internal override returns (bool) {
        if (super._isAllowedRewardContract(_rewardContract, _pool)) {
            return true;
        }
        return allowedRewardContracts.contains(_rewardContract);
    }
}
