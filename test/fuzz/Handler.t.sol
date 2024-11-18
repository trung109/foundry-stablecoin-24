// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DSCEngine dsce;
    DecentralizedStableCoin dsc;

    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 public timesMintIsCalled;
    address[] public users;
    MockV3Aggregator wethPriceFeed;
    MockV3Aggregator wbtcPriceFeed;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DSCEngine _dsce, DecentralizedStableCoin _dsc) {
        dsce = _dsce;
        dsc = _dsc;
        address[] memory tokens = dsce.getCollateralTokens();
        weth = ERC20Mock(tokens[0]);
        wbtc = ERC20Mock(tokens[1]);

        wethPriceFeed = MockV3Aggregator(
            dsce.getCollateralTokenPriceFeed(address(weth))
        );
        wbtcPriceFeed = MockV3Aggregator(
            dsce.getCollateralTokenPriceFeed(address(wbtc))
        );
    }

    function depositCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral
    ) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dsce), amountCollateral);
        dsce.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        users.push(msg.sender);
    }

    function mintDsc(uint256 amount, uint256 userSeed) public {
        if (users.length == 0) {
            return;
        }
        address sender = users[userSeed % users.length];
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce
            .getAccountInformation(sender);
        int256 maxDscToMint = (int256(collateralValueInUsd) / 2) -
            int256(totalDscMinted);

        if (maxDscToMint < 0) {
            return;
        }
        amount = bound(amount, 0, uint256(maxDscToMint));
        if (amount == 0) {
            return;
        }
        vm.prank(sender);
        dsce.mintDsc(amount);

        timesMintIsCalled++;
    }

    function redeemCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral,
        uint256 userSeed
    ) public {
        if (users.length == 0) {
            return;
        }
        address sender = users[userSeed % users.length];
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);

        (uint256 totalDscMinted, ) = dsce.getAccountInformation(sender);
        uint256 collateralBalance = dsce.getCollateralBalanceOfUser(
            sender,
            address(collateral)
        );
        uint256 collateralBalanceInUsd = dsce.getUsdValue(
            address(collateral),
            collateralBalance
        );

        if (collateralBalanceInUsd <= totalDscMinted * 2) {
            return;
        }
        uint256 maxCollateralToRedeemInUsd = collateralBalanceInUsd -
            totalDscMinted *
            2;
        uint256 maxCollateralToRedeem = dsce.getTokenAmountFromUsd(
            address(collateral),
            maxCollateralToRedeemInUsd
        );

        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        if (amountCollateral == 0) {
            return;
        }
        vm.prank(sender);
        dsce.redeemCollateral(address(collateral), amountCollateral);
    }

    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     wethPriceFeed.updateAnswer(newPriceInt);
    // }

    // Helper functions

    function _getCollateralFromSeed(
        uint256 seed
    ) private view returns (ERC20Mock) {
        if (seed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }
}
