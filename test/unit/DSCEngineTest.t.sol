// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;

    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address wbtc;

    address public constant FORGE_TEST_ADDRESS =
        0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
    address public USER = makeAddr("user");
    address public USER_2 = makeAddr("user2");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 20 ether;
    uint256 public constant STARTING_DSC_MINT_AMOUNT = 1000 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, ) = config
            .activeNetworkConfig();
        // if (block.chainid == 31337) {
        //     vm.deal(USER, STARTING_ERC20_BALANCE);
        // }
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    /*//////////////////////////////////////////////////////////////
                           CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthMismatch() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(
            DSCEngine
                .DSCEngine__TokenAddressesAndPriceFeedAddresseseMustBeSameLength
                .selector
        );
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    /*//////////////////////////////////////////////////////////////
                              PRICE TESTS
    //////////////////////////////////////////////////////////////*/
    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        uint256 expectedUsdValue = (45000e18);
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        assertEq(expectedUsdValue, actualUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 45e18;
        uint256 expectedWeth = 0.015e18;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT COLLATERAL TESTS
    //////////////////////////////////////////////////////////////*/

    modifier depositCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertWithUnapprovedCollateral() public {
        ERC20Mock randToken = new ERC20Mock("RAN", "RAN", USER, 100 ether);
        randToken.mint(USER, STARTING_ERC20_BALANCE);
        vm.startPrank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__NotAllowedToken.selector,
                address(randToken)
            )
        );
        dsce.depositCollateral(address(randToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCanDepositCollateralAndGetAccountInfo()
        public
        depositCollateral
    {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce
            .getAccountInformation(USER);
        assertEq(totalDscMinted, 0);
        uint256 expectedDepositAmount = dsce.getTokenAmountFromUsd(
            weth,
            collateralValueInUsd
        );
        assertEq(expectedDepositAmount, AMOUNT_COLLATERAL);
    }

    /*//////////////////////////////////////////////////////////////
                             MINT DSC TESTS
    //////////////////////////////////////////////////////////////*/

    function testRevertsIfAmountToMintIsZero() public depositCollateral {
        vm.startPrank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__NeedsMoreThanZero.selector
            )
        );
        dsce.mintDsc(0);
        vm.stopPrank();
    }

    function testRevertsIfHealthBrokenAfterMint() public depositCollateral {
        vm.startPrank(USER);
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce
            .getAccountInformation(USER);
        uint256 amountToMint = collateralValueInUsd - totalDscMinted + 1;
        uint256 expectedHealthFactor = dsce.calculateHealthFactor(
            totalDscMinted + amountToMint,
            collateralValueInUsd
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__BreakHealthFactor.selector,
                expectedHealthFactor
            )
        );
        dsce.mintDsc(amountToMint);
        vm.stopPrank();
    }

    function testMintDscSuccess() public depositCollateral {
        vm.startPrank(USER);
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce
            .getAccountInformation(USER);
        uint256 initialDscMinted = totalDscMinted;
        uint256 amountToMint = STARTING_DSC_MINT_AMOUNT;
        console.log(collateralValueInUsd);
        dsce.mintDsc(amountToMint);
        (totalDscMinted, collateralValueInUsd) = dsce.getAccountInformation(
            USER
        );
        assertEq(totalDscMinted, initialDscMinted + amountToMint);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                  DEPOSIT COLLATERAL & MINT DSC TESTS
    //////////////////////////////////////////////////////////////*/

    function testDepositCollateralAndMintDscSuccess() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(
            weth,
            AMOUNT_COLLATERAL,
            STARTING_DSC_MINT_AMOUNT
        );
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce
            .getAccountInformation(USER);
        assertEq(totalDscMinted, STARTING_DSC_MINT_AMOUNT);
        uint256 expectedDepositAmount = dsce.getTokenAmountFromUsd(
            weth,
            collateralValueInUsd
        );
        assertEq(expectedDepositAmount, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        REDEEM COLLATERAL TESTS
    //////////////////////////////////////////////////////////////*/
    modifier depositCollateralAndMintDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(
            weth,
            AMOUNT_COLLATERAL,
            STARTING_DSC_MINT_AMOUNT
        );
        vm.stopPrank();
        _;
    }
    function testRevertsIfAmountToRedeemIsZero()
        public
        depositCollateralAndMintDsc
    {
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__NeedsMoreThanZero.selector
            )
        );
        dsce.redeemCollateral(weth, 0);
    }

    function testRevertsIfHealthBrokenAfterRedeem()
        public
        depositCollateralAndMintDsc
    {
        vm.startPrank(USER);
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce
            .getAccountInformation(USER);
        uint256 amountToRedeemInUsd = collateralValueInUsd;
        uint256 amountToRedeem = dsce.getTokenAmountFromUsd(
            weth,
            amountToRedeemInUsd
        );
        uint256 expectedHealthFactor = dsce.calculateHealthFactor(
            totalDscMinted,
            collateralValueInUsd - amountToRedeemInUsd
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__BreakHealthFactor.selector,
                expectedHealthFactor
            )
        );
        dsce.redeemCollateral(weth, amountToRedeem);
        vm.stopPrank();
    }

    function testRevertsIfRedeemUnapprovedToken()
        public
        depositCollateralAndMintDsc
    {
        ERC20Mock randToken = new ERC20Mock("RAN", "RAN", USER, 100 ether);
        randToken.mint(USER, STARTING_ERC20_BALANCE);
        vm.startPrank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__NotAllowedToken.selector,
                address(randToken)
            )
        );
        dsce.redeemCollateral(address(randToken), 1);
        vm.stopPrank();
    }

    function testRedeemCollateralSuccess() public depositCollateralAndMintDsc {
        vm.startPrank(USER);
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce
            .getAccountInformation(USER);
        uint256 initialCollateralInUsd = collateralValueInUsd;
        uint256 amountToRedeemInUsd = collateralValueInUsd / 10;
        uint256 amountToRedeem = dsce.getTokenAmountFromUsd(
            weth,
            amountToRedeemInUsd
        );
        dsce.redeemCollateral(weth, amountToRedeem);
        (totalDscMinted, collateralValueInUsd) = dsce.getAccountInformation(
            USER
        );
        assertEq(
            collateralValueInUsd,
            initialCollateralInUsd - amountToRedeemInUsd
        );
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                             BURN DSC TESTS
    //////////////////////////////////////////////////////////////*/

    function testRevertsIfAmountToBurnIsZero()
        public
        depositCollateralAndMintDsc
    {
        vm.startPrank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__NeedsMoreThanZero.selector
            )
        );
        dsce.burnDsc(0);
        vm.stopPrank();
    }

    function testRevertsIfBurnMoreThanMintedDsc()
        public
        depositCollateralAndMintDsc
    {
        vm.startPrank(USER);
        (uint256 totalDscMinted, ) = dsce.getAccountInformation(USER);
        uint256 amountToBurn = totalDscMinted + 1;
        vm.expectRevert();
        dsce.burnDsc(amountToBurn);
        vm.stopPrank();
    }

    function testBurnSuccess() public depositCollateralAndMintDsc {
        vm.startPrank(USER);
        dsc.approve(address(dsce), STARTING_DSC_MINT_AMOUNT);
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce
            .getAccountInformation(USER);
        uint256 initialDscMinted = totalDscMinted;
        uint256 amountToBurn = totalDscMinted - 1;
        dsce.burnDsc(amountToBurn);
        (totalDscMinted, collateralValueInUsd) = dsce.getAccountInformation(
            USER
        );
        assertEq(totalDscMinted, initialDscMinted - amountToBurn);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                   REDEEM COLLATERAL & BURN DSC TESTS
    //////////////////////////////////////////////////////////////*/

    function testBurnDscAndRedeemCollateralSuccess()
        public
        depositCollateralAndMintDsc
    {
        vm.startPrank(USER);
        (uint256 initialDscMinted, uint256 initialCollateralValueInUsd) = dsce
            .getAccountInformation(USER);
        dsc.approve(address(dsce), initialDscMinted);
        dsce.burnDscAndRedeemCollateral(
            weth,
            AMOUNT_COLLATERAL,
            initialDscMinted
        );
        uint256 collateralValueInUsdLeft = initialCollateralValueInUsd -
            dsce.getUsdValue(weth, AMOUNT_COLLATERAL);
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce
            .getAccountInformation(USER);

        assertEq(totalDscMinted, 0);
        assertEq(collateralValueInUsdLeft, collateralValueInUsd);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            LIQUIDATE TESTS
    //////////////////////////////////////////////////////////////*/

    modifier fundUser2() {
        if (ERC20Mock(weth).balanceOf(USER_2) == 0) {
            ERC20Mock(weth).mint(USER_2, STARTING_ERC20_BALANCE * 10);
        }
        vm.startPrank(USER_2);
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce
            .getAccountInformation(USER_2);
        if (collateralValueInUsd == 0) {
            ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL * 10);
            dsce.depositCollateralAndMintDsc(
                weth,
                AMOUNT_COLLATERAL * 10,
                STARTING_DSC_MINT_AMOUNT * 10
            );
        }
        vm.stopPrank();
        _;
    }

    modifier healthFactorNotOk() {
        // Minted 9000 DSC more = 9000 USD
        vm.prank(USER);
        dsce.mintDsc(9000 ether);
        // Update price feed to 1 ETH = 1500 USD
        int256 ethUsdUpdatedPrice = 1500e8;
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        // Health factor now is 0.75
        // Minted 10000 DSC = 10000 USD
        // Collateral value = 15000 USD
        // Need to burn at least 5556 USD to improve health factor
        // 15000 - 1.1y >= 20000 - 2y
        _;
    }

    function testRevertsIfHealthFactorOk()
        public
        depositCollateralAndMintDsc
        fundUser2
    {
        vm.startPrank(USER_2);
        vm.expectRevert(
            abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorOk.selector)
        );
        dsce.liquidate(weth, USER, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRevertsIfHealthFactorNotImprovedAfterLiquidation()
        public
        depositCollateralAndMintDsc
        fundUser2
        healthFactorNotOk
    {
        vm.startPrank(USER_2);
        uint256 burnAmountLessThanMinimum = 5555e18;
        dsc.approve(address(dsce), burnAmountLessThanMinimum);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__HealthFactorNotImproved.selector
            )
        );
        dsce.liquidate(weth, USER, burnAmountLessThanMinimum);
        vm.stopPrank();
    }

    function testLiquidateSuccess()
        public
        depositCollateralAndMintDsc
        fundUser2
        healthFactorNotOk
    {
        vm.startPrank(USER_2);
        uint256 minimumValidBurnAmount = 5556e18;
        dsc.approve(address(dsce), minimumValidBurnAmount);

        dsce.liquidate(weth, USER, minimumValidBurnAmount);

        uint256 liquidatorWethBalance = ERC20Mock(weth).balanceOf(USER_2);
        uint256 liquidatedWethGot = dsce.getTokenAmountFromUsd(
            weth,
            minimumValidBurnAmount
        ) +
            (dsce.getTokenAmountFromUsd(weth, minimumValidBurnAmount) /
                dsce.getLiquidationBonus());
        uint256 expectedWeth = STARTING_ERC20_BALANCE *
            10 -
            AMOUNT_COLLATERAL *
            10 +
            liquidatedWethGot;
        assertEq(liquidatorWethBalance, expectedWeth);
        vm.stopPrank();
    }

    function testBalanceIsCorrectAfterLiquidation()
        public
        depositCollateralAndMintDsc
        fundUser2
        healthFactorNotOk
    {
        // Before
        vm.startPrank(USER_2);
        uint256 minimumValidBurnAmount = 5556e18;
        (
            uint256 totalDscMintedBefore1,
            uint256 collateralValueInUsdBefore1
        ) = dsce.getAccountInformation(USER);
        // Note: User2 DSC minted stay the same.
        // Note: User DSC balance stay the same.
        uint256 dscBalanceBefore = dsc.balanceOf(USER_2);

        // Liquidation
        dsc.approve(address(dsce), minimumValidBurnAmount);
        dsce.liquidate(weth, USER, minimumValidBurnAmount);

        // After
        (
            uint256 totalDscMintedAfter1,
            uint256 collateralValueInUsdAfter1
        ) = dsce.getAccountInformation(USER);
        uint256 dscBalanceAfter = dsc.balanceOf(USER_2);

        // Asserts
        // Note: Already test the collaterValueInUsd of User2 in the previous test
        assertEq(
            collateralValueInUsdAfter1,
            collateralValueInUsdBefore1 - (minimumValidBurnAmount * 110) / 100
        );
        assertEq(
            totalDscMintedAfter1,
            totalDscMintedBefore1 - minimumValidBurnAmount
        );
        assertEq(dscBalanceAfter, dscBalanceBefore - minimumValidBurnAmount);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                          HEALTH FACTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function testHealthFactorEqualMaxWhenNotMinted() public depositCollateral {
        uint256 actualHealthFactor = dsce.getHealthFactor(USER);
        assertEq(type(uint256).max, actualHealthFactor);
    }

    function testHealthFactor() public depositCollateralAndMintDsc {
        // Deposited 10 ETH = 30000 USD
        // Minted 1000 DSC = 1000 USD
        // Health Factor = ((30000 * 50) / 100) / 1000 = 15
        uint256 expectedHealthFactor = 15e18;
        uint256 actualHealthFactor = dsce.getHealthFactor(USER);
        assertEq(expectedHealthFactor, actualHealthFactor);
    }

    function testCalculateHealthFactorEqualMaxWhenNotMinted()
        public
        depositCollateral
    {
        uint256 actualHealthFactor = dsce.calculateHealthFactor(
            0,
            AMOUNT_COLLATERAL
        );
        assertEq(type(uint256).max, actualHealthFactor);
    }

    function testCalculateHealthFactor() public depositCollateralAndMintDsc {
        // Deposited 10 ETH = 15000 USD (price dropped in the future)
        // Minted 1000 DSC = 1000 USD
        // Minted 9000 DSC more = 9000 USD
        vm.prank(USER);
        dsce.mintDsc(9000 ether);
        // Health Factor = ((15000 * 50) / 100) / 10000 = 0.75

        int256 ethUsdUpdatedPrice = 1500e8;
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        uint256 expectedHealthFactor = 0.75e18;
        uint256 collateralValueInUsd = dsce.getUsdValue(
            weth,
            AMOUNT_COLLATERAL
        );
        uint256 totalDscMinted = 10000e18;

        uint256 actualHealthFactor = dsce.calculateHealthFactor(
            totalDscMinted,
            collateralValueInUsd
        );
        assertEq(expectedHealthFactor, actualHealthFactor);
    }

    /*//////////////////////////////////////////////////////////////
                    VIEW & EXTERNAL FUNCTIONS TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetCollateralTokens() public view {
        address[] memory expectedCollateralTokens = new address[](1);
        expectedCollateralTokens[0] = weth;
        address[] memory actualCollateralTokens = dsce.getCollateralTokens();
        assertEq(expectedCollateralTokens[0], actualCollateralTokens[0]);
    }

    function testGetDsc() public view {
        address expectedDsc = address(dsc);
        address actualDsc = dsce.getDsc();
        assertEq(expectedDsc, actualDsc);
    }

    function testGetCollateralTokenPriceFeed() public view {
        address expectedPriceFeed = ethUsdPriceFeed;
        address actualPriceFeed = dsce.getCollateralTokenPriceFeed(weth);
        assertEq(expectedPriceFeed, actualPriceFeed);
    }

    function testGetAccountInformation() public depositCollateralAndMintDsc {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce
            .getAccountInformation(USER);
        uint256 expectedCollateralValueInUsd = dsce.getUsdValue(
            weth,
            AMOUNT_COLLATERAL
        );
        assertEq(totalDscMinted, STARTING_DSC_MINT_AMOUNT);
        assertEq(collateralValueInUsd, expectedCollateralValueInUsd);
    }

    function testGetCollateralBalanceOfUser()
        public
        depositCollateralAndMintDsc
    {
        uint256 expectedBalance = AMOUNT_COLLATERAL;
        uint256 actualBalance = dsce.getCollateralBalanceOfUser(USER, weth);
        assertEq(expectedBalance, actualBalance);
    }

    function testGetAccountCollateralValue()
        public
        depositCollateralAndMintDsc
    {
        uint256 expectedValueInUsd = dsce.getUsdValue(weth, AMOUNT_COLLATERAL);
        uint256 actualValue = dsce.getAccountCollateralValue(USER);
        assertEq(expectedValueInUsd, actualValue);
    }

    function testGetPresion() public view {
        uint256 expectedPrecision = 1e18;
        uint256 actualPrecision = dsce.getPrecision();
        assertEq(expectedPrecision, actualPrecision);
    }

    function testGetAdditionalFeedPrecision() public view {
        uint256 expectedPrecision = 1e10;
        uint256 actualPrecision = dsce.getAdditionalFeedPrecision();
        assertEq(expectedPrecision, actualPrecision);
    }

    function testGetLiquidationThreshold() public view {
        uint256 expectedThreshold = 50;
        uint256 actualThreshold = dsce.getLiquidationThreshold();
        assertEq(expectedThreshold, actualThreshold);
    }

    function testGetLiquidationBonus() public view {
        uint256 expectedBonus = 10;
        uint256 actualBonus = dsce.getLiquidationBonus();
        assertEq(expectedBonus, actualBonus);
    }

    function testGetLiquidationPrecision() public view {
        uint256 expectedPrecision = 100;
        uint256 actualPrecision = dsce.getLiquidationPrecision();
        assertEq(expectedPrecision, actualPrecision);
    }

    function testGetMinHealthFactor() public view {
        uint256 expectedMinHealthFactor = 1e18;
        uint256 actualMinHealthFactor = dsce.getMinHealthFactor();
        assertEq(expectedMinHealthFactor, actualMinHealthFactor);
    }
}
