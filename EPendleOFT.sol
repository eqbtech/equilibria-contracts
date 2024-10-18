// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@layerzerolabs/solidity-examples/contracts/token/oft/v2/OFTV2.sol";

contract EPendleOFT is OFTV2 {
    constructor(
        string memory _name,
        string memory _symbol,
        address _lzEndpoint
    ) OFTV2(_name, _symbol, 8, _lzEndpoint) {}
}
