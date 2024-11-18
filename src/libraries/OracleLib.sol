// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracleLib
 * @author Osprey
 * @notice This library is used to check the ChainLink oracle for stale data.
 * If a price stale, the function will revert, and render the DSCEngine unusable - this is by design
 * We want the DSCEngine to freeeze if prices beacome stale.
 *
 * So if the ChainLink network explodes and you have a lot of money locked in the protocol...
 */

library OracleLib {
    error OracleLib__StalePrice();
    uint256 private constant TIMEOUT = 3 hours;

    function staleCheckLatestRoundData(
        AggregatorV3Interface priceFeed
    ) public view returns (uint80, int256, uint256, uint256, uint80) {
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();
        if (updatedAt == 0 || answeredInRound < roundId) {
            revert OracleLib__StalePrice();
        }
        uint256 secondsSince = block.timestamp - updatedAt;

        if (secondsSince > TIMEOUT) revert OracleLib__StalePrice();
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }

    function getTimeout(
        AggregatorV3Interface /* chainlinkFeed */
    ) public pure returns (uint256) {
        return TIMEOUT;
    }
}
