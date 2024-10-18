// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ILybraProxy {
    function isValidVault(address _vault) external view returns (bool);

    function getVaultWeight(address _vault) external view returns (uint256);

    function depositEtherToVault(
        address _vault,
        uint256 _mintAmount
    ) external payable returns (uint256);

    function depositAssetToVault(
        address _vault,
        uint256 _assetAmount,
        uint256 _mintAmount
    ) external returns (uint256);

    function withdrawFromVault(
        address _vault,
        address _onBehalfOf,
        uint256 _amount
    ) external returns (uint256);

    function borrowFromVault(address _vault, uint256 _amount) external;

    function repayVault(address _vault, uint256 _amount) external;

    function lock(uint256 _amount, bool _useLBR) external;

    function stake(uint256 _amount) external;

    function unstake(uint256 _amount) external;

    function withdrawLBR(uint256 _amount) external;

    function getProtocolRewards()
        external
        returns (address[] memory rewardTokens, uint256[] memory rewardAmounts);

    function stakeEthLbrLp(uint256 _amount) external;

    function withdrawEthLbrLp(uint256 _amount) external;

    function getEthLbrStakePoolRewards() external returns (uint256);

    function getEUSDMiningIncentives() external returns (uint256);
}
