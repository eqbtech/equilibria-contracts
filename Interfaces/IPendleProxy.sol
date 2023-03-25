// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface IPendleProxy {
    function isValidMarket(address _market) external view returns (bool);

    function withdraw(address _market, address _to, uint256 _amount) external;

    function claimRewards(
        address _market
    ) external returns (address[] memory, uint256[] memory);

    function lockPendle(uint128 _expiry) external;

    // --- Events ---
    event BoosterUpdated(address _booster);
    event DepositorUpdated(address _depositor);

    event Withdrawn(address _market, address _to, uint256 _amount);

    event RewardsClaimed(
        address _market,
        address[] _rewardTokens,
        uint256[] _rewardAmounts
    );

    event PendleLocked(uint128 _additionalAmountToLock, uint128 _newExpiry);
}
