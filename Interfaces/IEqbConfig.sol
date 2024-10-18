// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IEqbConfig {
    function getContract(bytes32 _contractKey) external view returns (address);

    event ContractSet(
        bytes32 indexed _contractKey,
        address indexed _contractAddress
    );
}
