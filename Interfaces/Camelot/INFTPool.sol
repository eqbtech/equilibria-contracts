// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface INFTPool {
    function createPosition(uint256 _amount, uint256 _duration) external;
    function harvestPosition(uint256 _tokenId) external;
    function addToPosition(uint256 _tokenId, uint256 _amount) external;
    function withdrawFromPosition(uint256 _tokenId, uint256 _amount) external;
    function getPoolInfo() external returns(address _lpAddress, address _grailToken, address _xGrailToken, uint256, uint256, uint256, uint256, uint256);
    function pendingRewards(uint256 _tokenId) external view returns (uint256);
    function getStakingPosition(uint256 tokenId) external view returns(uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256);
}