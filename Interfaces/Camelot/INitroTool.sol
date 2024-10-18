// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IXGrailToken is IERC20 {
    function usageAllocations(address userAddress, address usageAddress) external view returns (uint256 allocation);

    function allocateFromUsage(address userAddress, uint256 amount) external;
    function convertTo(uint256 amount, address to) external;
    function deallocateFromUsage(address userAddress, uint256 amount) external;

    function isTransferWhitelisted(address account) external view returns (bool);
}

interface IGrailTokenV2 is IERC20{
    function lastEmissionTime() external view returns (uint256);

    function claimMasterRewards(uint256 amount) external returns (uint256 effectiveAmount);
    function masterEmissionRate() external view returns (uint256);
    function burn(uint256 amount) external;
}

interface INitroCustomReq {
    function canDepositDescription() external view returns (string calldata);
    function canHarvestDescription() external view returns (string calldata);

    function canDeposit(address user, uint256 tokenId) external view returns (bool);
    function canHarvest(address user) external view returns (bool);
}

interface INFTHandler is IERC721Receiver {
    function onNFTHarvest(address operator, address to, uint256 tokenId, uint256 grailAmount, uint256 xGrailAmount) external returns (bool);
    function onNFTAddToPosition(address operator, uint256 tokenId, uint256 lpAmount) external returns (bool);
    function onNFTWithdraw(address operator, uint256 tokenId, uint256 lpAmount) external returns (bool);
}

interface INitroPoolFactory {
    function emergencyRecoveryAddress() external view returns (address);
    function feeAddress() external view returns (address);
    function getNitroPoolFee(address nitroPoolAddress, address ownerAddress) external view returns (uint256);
    function publishNitroPool(address nftAddress) external;
    function setNitroPoolOwner(address previousOwner, address newOwner) external;
}

interface ICamelotMaster {

    function grailToken() external view returns (address);
    function yieldBooster() external view returns (address);
    function owner() external view returns (address);
    function emergencyUnlock() external view returns (bool);

    function getPoolInfo(address _poolAddress) external view returns (address poolAddress, uint256 allocPoint, uint256 lastRewardTime, uint256 reserve, uint256 poolEmissionRate);

    function claimRewards() external returns (uint256);
}

interface IYieldBooster {
    function deallocateAllFromPool(address userAddress, uint256 tokenId) external;
    function getMultiplier(address poolAddress, uint256 maxBoostMultiplier, uint256 amount, uint256 totalPoolSupply, uint256 allocatedAmount) external view returns (uint256);
}

interface INFTPool is IERC721 {
  function exists(uint256 tokenId) external view returns (bool);
  function hasDeposits() external view returns (bool);
  function getPoolInfo() external view returns (
    address lpToken, address grailToken, address sbtToken, uint256 lastRewardTime, uint256 accRewardsPerShare,
    uint256 lpSupply, uint256 lpSupplyWithMultiplier, uint256 allocPoint
  );
  function getStakingPosition(uint256 tokenId) external view returns (
    uint256 amount, uint256 amountWithMultiplier, uint256 startLockTime,
    uint256 lockDuration, uint256 lockMultiplier, uint256 rewardDebt,
    uint256 boostPoints, uint256 totalMultiplier
  );

  function boost(uint256 userAddress, uint256 amount) external;
  function unboost(uint256 userAddress, uint256 amount) external;
}