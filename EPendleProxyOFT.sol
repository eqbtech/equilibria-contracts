// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@layerzerolabs/solidity-examples/contracts/token/oft/v2/ProxyOFTV2.sol";

contract EPendleProxyOFT is ProxyOFTV2 {
    constructor(
        address _token,
        address _layerZeroEndpoint
    ) ProxyOFTV2(_token, 8, _layerZeroEndpoint) {}
}
