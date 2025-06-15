// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

library EqbConstants {
    // Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant ZAP_ROLE = keccak256("ZAP_ROLE");

    // contracts
    bytes32 public constant PENDLE_ROUTER_V3 = keccak256("PENDLE_ROUTER_V3");
    bytes32 public constant DEPOSIT_TOKEN_V2_BEACON =
        keccak256("DEPOSIT_TOKEN_V2_BEACON");
    bytes32 public constant BASE_REWARD_POOL_V2_BEACON =
        keccak256("BASE_REWARD_POOL_V2_BEACON");
    bytes32 public constant EPENDLE_VAULT_SIDECHAIN =
        keccak256("EPENDLE_VAULT_SIDECHAIN");
    bytes32 public constant SMART_CONVERTOR = keccak256("SMART_CONVERTOR");
    bytes32 public constant EQB_ZAP = keccak256("EQB_ZAP");
    bytes32 public constant VAULT_DEPOSIT_TOKEN_BEACON =
        keccak256("VAULT_DEPOSIT_TOKEN_BEACON");
}
