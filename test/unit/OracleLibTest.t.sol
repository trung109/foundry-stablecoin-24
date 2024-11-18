// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {OracleLib, AggregatorV3Interface} from "../../src/libraries/OracleLib.sol";

contract OracleLibTest is Test {
    using OracleLib for AggregatorV3Interface;

    MockV3Aggregator public priceFeed;
    uint8 public constant DECIMALS = 8;
    int256 public constant INITIAL_PRICE = 3000 ether;

    function setUp() public {
        priceFeed = new MockV3Aggregator(DECIMALS, INITIAL_PRICE);
    }

    function testGetTimeout() public view {
        uint256 expectedTimeout = 3 hours;
        assertEq(
            OracleLib.getTimeout(AggregatorV3Interface(address(priceFeed))),
            expectedTimeout
        );
    }

    function testPriceRevertsOnStaleCheck() public {
        vm.warp(block.timestamp + 4 hours + 1 seconds);
        vm.roll(block.number + 1);

        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        AggregatorV3Interface(address(priceFeed)).staleCheckLatestRoundData();
    }

    function testpriceRevertsOnBadAnsweredInRound() public {
        uint80 _roundId = 0;
        int256 _answer = 0;
        uint256 _timestamp = 0;
        uint256 _startedAt = 0;

        priceFeed.updateRoundData(_roundId, _answer, _timestamp, _startedAt);

        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        AggregatorV3Interface(address(priceFeed)).staleCheckLatestRoundData();
    }
}
