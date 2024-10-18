// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IRewards.sol";

interface ILybraBooster is IRewards {
    event VaultAdded(address _vault);

    event Deposited(
        address indexed _user,
        address indexed _vault,
        uint256 _etherAmount,
        uint256 _assetAmount,
        uint256 _depositedAmount
    );

    event Withdrawn(
        address indexed _user,
        address indexed _vault,
        uint256 _amount,
        uint256 _withdrawAmount
    );

    event RewardTokenAdded(
        address indexed _vault,
        address indexed _rewardToken
    );
    event VaultRewardAdded(
        address indexed _vault,
        address indexed _rewardToken,
        uint256 _reward
    );
    event RewardPaid(
        address indexed _vault,
        address indexed _user,
        address indexed _rewardToken,
        uint256 _reward
    );
}
