// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

library LayerZeroHelper {
    function getLayerZeroChainId(
        uint256 chainId
    ) internal pure returns (uint16) {
        if (chainId == 1) {
            // ethereum
            return 101;
        } else if (chainId == 42161) {
            // arbitrum one
            return 110;
        } else if (chainId == 43113) {
            // fuji testnet
            return 10106;
        } else if (chainId == 80001) {
            // mumbai testnet
            return 10109;
        }
        assert(false);
    }

    function getOriginalChainId(
        uint16 chainId
    ) internal pure returns (uint256) {
        if (chainId == 101) {
            // ethereum
            return 1;
        } else if (chainId == 110) {
            // arbitrum one
            return 42161;
        } else if (chainId == 10106) {
            // fuji testnet
            return 43113;
        } else if (chainId == 10109) {
            // mumbai testnet
            return 80001;
        }
        assert(false);
    }
}
