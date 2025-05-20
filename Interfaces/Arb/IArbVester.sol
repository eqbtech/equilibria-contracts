// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IArbVester {
    event ArbAdded(address indexed user, uint256 amount);
    event VestingPositionAdded(
        address indexed user,
        uint256 amount,
        uint256 lpAmount,
        uint256 durationWeeks,
        uint256 start,
        uint256 vestId,
        bool vestInNft
    );
    event VestingPositionClosed(
        address indexed user,
        uint256 amount,
        uint256 vestId,
        uint256 usdtAmount
    );
    event VestingPositionUnlocked(
        address indexed user,
        uint256 amount,
        uint256 vestId,
        bool vestInNft
    );
    event Withdrawn(address indexed user, uint256 usdtAmount, uint256 amount);
    event ClaimedReward(
        address indexed user,
        address indexed asset,
        uint256 amount,
        uint256 totalClaimedAmount
    );
    event TotalLpChanged(uint256 totalLpLocked, bool income, uint256 amount);
    event UnlockInAdvance(uint256 indexed vestId);

    struct VestingPosition {
        address user;
        uint256 amount;
        uint256 lpAmount;
        uint256 durationWeeks;
        uint256 start;
        uint256 nftTokenId;
        bool closed;
        bool unlocked;
    }

    struct Reward {
        uint256 claimedAmount;
        // nitroPoolRewards
        uint256 rewardPerShare;
        // nftPoolRewards
        uint256 pendingAmount;
    }

    function adminAddArb(uint256 _amount) external;

    function vestNft(
        uint256 _amount,
        uint256 _weeks,
        uint256 _nftTokenId
    ) external;

    function vest(uint256 _amount, uint256 _weeks) external;

    function closeVestingPosition(uint256 _vestId, uint256 _maxAmount) external;

    function unlock(uint256 _vestId) external;

    function unlockInAdvance(uint256 _vestId) external;

    function adminWithdraw(uint256 _amount) external;

    function claimRewards(uint256 _vestId) external;

    function getRewardTokens() external view returns (address[] memory);

    function getPendingRewards(
        uint256 _vestId
    ) external view returns (uint256[] memory);

    function getVestingPosition(
        uint256 _vestId
    ) external view returns (VestingPosition memory);

    function getUserVestingPositions(
        address _user
    ) external view returns (uint256[] memory);

    function calculateVestingAmount(
        uint256 _amount,
        uint256 _weeks,
        uint256 _realLockWeeks
    ) external view returns (uint256);

    function calculateLpAmount(
        uint256 _arbAmount
    ) external view returns (uint256);
}
