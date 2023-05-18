// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface IVestedEscrow {
    function fund(
        address[] calldata _recipients,
        uint256[] calldata _amounts
    ) external;

    event Funded(address indexed _recipient, uint256 _amount);
    event Claimed(address indexed _recipient, uint256 _amount);
}
