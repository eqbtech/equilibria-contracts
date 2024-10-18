// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IPMerkleDistributor {
    function claim(
        address receiver,
        uint256 totalAccrued,
        bytes32[] calldata proof
    ) external returns (uint256 amountOut);

    function claimVerified(
        address receiver
    ) external returns (uint256 amountOut);

    function verify(
        address user,
        uint256 totalAccrued,
        bytes32[] calldata proof
    ) external returns (uint256 amountVerified);
}
