// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IEqbConfig {
    function getContract(bytes32 _contractKey) external view returns (address);

    function getLayerZeroChainId(
        uint256 _chainId
    ) external view returns (uint16);

    function getOriginalChainId(
        uint16 _chainId
    ) external view returns (uint256);

    event ContractSet(
        bytes32 indexed _contractKey,
        address indexed _contractAddress
    );

    event LayerZeroChainIdSet(
        uint256 indexed _chainId,
        uint16 indexed _lzChainId
    );

    event LayerZeroChainIdRemoved(
        uint256 indexed _chainId,
        uint16 indexed _lzChainId
    );
}
