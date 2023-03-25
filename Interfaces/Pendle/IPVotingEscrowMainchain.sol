// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IPVotingEscrowMainchain {
    function pendle() external view returns (address);

    function getAllDestinationContracts()
        external
        view
        returns (uint256[] memory chainIds, address[] memory addrs);

    function increaseLockPositionAndBroadcast(
        uint128 additionalAmountToLock,
        uint128 newExpiry,
        uint256[] calldata chainIds
    ) external payable returns (uint128 newVeBalance);
}
