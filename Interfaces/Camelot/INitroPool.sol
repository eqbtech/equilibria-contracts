// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface INitroPool {
    function nftPool() external view returns (address);
    function harvest() external;
    function withdraw(uint256 _tokenId) external;
    function rewardsToken1() external view returns (address, uint256, uint256, uint256);
    function rewardsToken2() external view returns (address, uint256, uint256, uint256);
}