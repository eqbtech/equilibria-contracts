// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Interfaces/Pendle/IPMerkleDistributor.sol";
import "./PendleProxyBaseUpg.sol";

contract PendleProxySidechain is PendleProxyBaseUpg {
    bytes32 public constant FEE_ADMIN_ROLE = keccak256("FEE_ADMIN_ROLE");

    function initialize() public initializer {
        __PendleProxyBaseUpg_init();
    }

    function setParams(
        address _pendleMarketFactory,
        address _booster
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setParams(_pendleMarketFactory, _booster);
    }

    function claim(
        address _merkleDistributor,
        address _receiver,
        uint256 _totalAccrued,
        bytes32[] calldata _proof
    ) external onlyRole(FEE_ADMIN_ROLE) returns (uint256 amountOut) {
        return
            IPMerkleDistributor(_merkleDistributor).claim(
                _receiver,
                _totalAccrued,
                _proof
            );
    }

    function claimVerified(
        address _merkleDistributor,
        address _receiver
    ) external onlyRole(FEE_ADMIN_ROLE) returns (uint256 amountOut) {
        return IPMerkleDistributor(_merkleDistributor).claimVerified(_receiver);
    }
}
