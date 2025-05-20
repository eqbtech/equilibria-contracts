// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import "./CrossChain/LayerZeroHelper.sol";
import "./Interfaces/IEqbConfig.sol";

contract EqbConfig is IEqbConfig, AccessControlUpgradeable {
    mapping(bytes32 => address) public contractMap;

    mapping(uint256 => uint16) public originalToLzChainIdMap;
    mapping(uint16 => uint256) public lzToOriginalChainIdMap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function setContract(
        bytes32 _contractKey,
        address _contractAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_contractAddress != address(0), "invalid _contractAddress!");
        require(
            contractMap[_contractKey] != _contractAddress,
            "_contractAddress already set!"
        );

        contractMap[_contractKey] = _contractAddress;
        emit ContractSet(_contractKey, _contractAddress);
    }

    function getContract(
        bytes32 _contractKey
    ) public view override returns (address) {
        return contractMap[_contractKey];
    }

    function setLayerZeroChainId(
        uint256 _chainId,
        uint16 _lzChainId
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(
            _chainId != 0 && _lzChainId != 0,
            "invalid chainId or lzChainId!"
        );
        require(
            lzToOriginalChainIdMap[_lzChainId] == 0 &&
                originalToLzChainIdMap[_chainId] == 0,
            "chainId already set!"
        );

        lzToOriginalChainIdMap[_lzChainId] = _chainId;
        originalToLzChainIdMap[_chainId] = _lzChainId;

        emit LayerZeroChainIdSet(_chainId, _lzChainId);
    }

    function removeByChainId(
        uint256 _chainId
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_chainId != 0, "invalid chainId!");

        uint16 lzChainId = originalToLzChainIdMap[_chainId];
        require(lzChainId != 0, "chainId not set!");

        delete originalToLzChainIdMap[_chainId];
        delete lzToOriginalChainIdMap[lzChainId];

        emit LayerZeroChainIdRemoved(_chainId, lzChainId);
    }

    function removeByLzChainId(
        uint16 _lzChainId
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_lzChainId != 0, "invalid lzChainId!");

        uint256 chainId = lzToOriginalChainIdMap[_lzChainId];
        require(chainId != 0, "lzChainId not set!");

        delete originalToLzChainIdMap[chainId];
        delete lzToOriginalChainIdMap[_lzChainId];

        emit LayerZeroChainIdRemoved(chainId, _lzChainId);
    }

    function getLayerZeroChainId(
        uint256 _chainId
    ) external view returns (uint16) {
        if (originalToLzChainIdMap[_chainId] != 0) {
            return originalToLzChainIdMap[_chainId];
        } else {
            return LayerZeroHelper.getLayerZeroChainId(_chainId);
        }
    }

    function getOriginalChainId(
        uint16 _chainId
    ) external view returns (uint256) {
        if (lzToOriginalChainIdMap[_chainId] != 0) {
            return lzToOriginalChainIdMap[_chainId];
        } else {
            return LayerZeroHelper.getOriginalChainId(_chainId);
        }
    }
}
