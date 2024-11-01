// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
import "../Interfaces/IOracle.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

interface IAggregatorV3Interface {
    function decimals() external view returns (uint8);

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

contract ChainlinkOracle is IOracle, AccessControlUpgradeable {
    IAggregatorV3Interface public priceFeed;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _priceFeed) external initializer {
        __AccessControl_init();

        require(_priceFeed != address(0), "invalid address");
        priceFeed = IAggregatorV3Interface(_priceFeed);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function getPrice() external view returns (uint256) {
        (, int256 price, , uint256 updatedAt, ) = priceFeed.latestRoundData();
        if (updatedAt < block.timestamp - 60 * 60 /* 1 hour */) {
            revert("stale price feed");
        }
        require(price > 0, "invalid price");
        return (uint256(price) * 1e18) / 10 ** uint256(priceFeed.decimals());
    }
}
