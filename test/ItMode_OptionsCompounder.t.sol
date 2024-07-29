// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.13;

import "./Common.sol";

import {BalancerOracle} from "../src/oracles/BalancerOracle.sol";
import {MockBalancerTwapOracle} from "../test/mocks/MockBalancerTwapOracle.sol";
// import {CErc20I} from "./strategies/interfaces/CErc20I.sol";
// import {Helper} from "./mocks/HelperFunctions.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
// import {IAToken} from "./strategies/interfaces/IAToken.sol";
// import {ReaperStrategyGranary, Externals} from "./strategies/ReaperStrategyGranary.sol";
import {OptionsCompounder} from "../src/OptionsCompounder.sol";
// import {MockedLendingPool} from "../test/mocks/MockedStrategy.sol";
import {ReaperSwapper, MinAmountOutData, MinAmountOutKind, IVeloRouter, ISwapRouter, UniV3SwapData} from "vault-v2/ReaperSwapper.sol";

contract ItModeOptionsCompounder is Common {
    using FixedPointMathLib for uint256;

    /* Variable assignment (depends on chain) */
    uint256 constant FORK_BLOCK = 9260950;
    string MAINNET_URL = vm.envString("MODE_RPC_URL");

    /* Contract variables */
    OptionsCompounder optionsCompounder;
    // ReaperStrategyGranary strategy;
    IOracle oracle;

    address[] strategies;

    function setUp() public {
        /* Common assignments */
        ExchangeType exchangeType = ExchangeType.VeloSolid;
        nativeToken = IERC20(MODE_WETH);
        paymentToken = IERC20(MODE_MODE);
        underlyingToken = IERC20(MODE_WETH);
        addressProvider = MODE_ADDRESS_PROVIDER;
        veloRouter = IVeloRouter(MODE_VELO_ROUTER);
        veloFactory = MODE_VELO_FACTORY;

        /* Setup network */
        uint256 fork = vm.createFork(MAINNET_URL, FORK_BLOCK);
        vm.selectFork(fork);

        /* Setup accounts */
        fixture_setupAccountsAndFees(3000, 7000);
        vm.deal(address(this), AMOUNT * 3);
        vm.deal(owner, AMOUNT * 3);

        /* Setup roles */
        address[] memory strategists = new address[](1);
        strategists[0] = strategist;

        /* Variables */

        /**
         * Contract deployments and configurations ***
         */

        /* Reaper deployment and configuration */
        reaperSwapper = new ReaperSwapper();
        tmpProxy = new ERC1967Proxy(address(reaperSwapper), "");
        reaperSwapper = ReaperSwapper(address(tmpProxy));
        reaperSwapper.initialize(strategists, address(this), address(this));

        /* Configure swapper */
        fixture_updateSwapperPaths(exchangeType);

        /* Oracle mocks deployment */
        oracle = fixture_getMockedOracle(exchangeType);

        /* Option token deployment */
        vm.startPrank(owner);
        optionsToken = new OptionsToken();
        tmpProxy = new ERC1967Proxy(address(optionsToken), "");
        optionsTokenProxy = OptionsToken(address(tmpProxy));
        optionsTokenProxy.initialize("TIT Call Option Token", "oTIT", tokenAdmin);

        /* Exercise contract deployment */
        SwapProps memory swapProps = fixture_getSwapProps(exchangeType, 200);
        uint256 minAmountToTriggerSwap = 1e5;
        exerciser = new DiscountExercise(
            optionsTokenProxy,
            owner,
            paymentToken,
            underlyingToken,
            oracle,
            PRICE_MULTIPLIER,
            INSTANT_EXIT_FEE,
            minAmountToTriggerSwap,
            treasuries,
            feeBPS,
            swapProps
        );
        /* Add exerciser to the list of options */

        optionsTokenProxy.setExerciseContract(address(exerciser), true);

        /* Strategy deployment */
        strategies.push(makeAddr("strategy"));
        optionsCompounder = new OptionsCompounder();
        tmpProxy = new ERC1967Proxy(address(optionsCompounder), "");
        optionsCompounder = OptionsCompounder(address(tmpProxy));
        console.log("Initializing...");
        optionsCompounder.initialize(address(optionsTokenProxy), address(addressProvider), swapProps, oracle, strategies);

        vm.stopPrank();

        /* Prepare EOA and contracts for tests */
        console.log("Dealing payment token..");
        uint256 maxPaymentAmount = AMOUNT * 2;
        deal(address(nativeToken), address(this), maxPaymentAmount);

        console.log("Calculation max amount of underlying..");
        maxUnderlyingAmount = maxPaymentAmount.divWadUp(oracle.getPrice());
        console.log("Max underlying amount to distribute: ", maxUnderlyingAmount);
        deal(address(underlyingToken), address(exerciser), maxUnderlyingAmount);
        underlyingToken.transfer(address(exerciser), maxUnderlyingAmount);

        /* Set up contracts */
        paymentToken.approve(address(exerciser), type(uint256).max);
    }

    function test_modeFlashloanPositiveScenario(uint256 amount) public {
        console.log("test_modeFlashloanPositiveScenario");
        /* Test vectors definition */
        amount = bound(amount, maxUnderlyingAmount / 10, underlyingToken.balanceOf(address(exerciser)));
        uint256 minAmount = 5;

        /* Prepare option tokens - distribute them to the specified strategy 
        and approve for spending */
        fixture_prepareOptionToken(amount, address(optionsCompounder), strategies[0], optionsTokenProxy, tokenAdmin);

        /* Check balances before compounding */
        uint256 paymentTokenBalance = paymentToken.balanceOf(strategies[0]);

        // vm.startPrank(address(strategy));
        /* already approved in fixture_prepareOptionToken */
        vm.prank(strategies[0]);
        optionsCompounder.harvestOTokens(amount, address(exerciser), minAmount);
        // vm.stopPrank();

        /* Assertions */
        assertGt(paymentToken.balanceOf(strategies[0]), paymentTokenBalance + minAmount, "Gain not greater than 0");
        assertEq(optionsTokenProxy.balanceOf(address(optionsCompounder)), 0, "Options token balance in compounder is 0");
        assertEq(paymentToken.balanceOf(address(optionsCompounder)), 0, "Payment token balance in compounder is 0");
    }

    function test_accessControlFunctionsChecks(address hacker, address randomOption, uint256 amount) public {
        /* Test vectors definition */
        amount = bound(amount, maxUnderlyingAmount / 10, underlyingToken.balanceOf(address(exerciser)));
        vm.assume(randomOption != address(0));
        vm.assume(hacker != owner);
        address addressProvider = makeAddr("AddressProvider");
        address[] memory strats = new address[](2);
        strats[0] = makeAddr("strat1");
        strats[1] = makeAddr("strat2");

        SwapProps memory swapProps = SwapProps(address(reaperSwapper), address(swapRouter), ExchangeType.UniV3, 200);

        /* Hacker tries to perform harvest */
        vm.startPrank(hacker);

        /* Hacker tries to manipulate contract configuration */
        vm.expectRevert("Ownable: caller is not the owner");
        optionsCompounder.setOptionsToken(randomOption);

        vm.expectRevert("Ownable: caller is not the owner");
        optionsCompounder.setSwapProps(swapProps);

        vm.expectRevert("Ownable: caller is not the owner");
        optionsCompounder.setOracle(oracle);

        vm.expectRevert("Ownable: caller is not the owner");
        optionsCompounder.setAddressProvider(addressProvider);

        vm.expectRevert("Ownable: caller is not the owner");
        optionsCompounder.setStrats(strats);

        vm.expectRevert("Ownable: caller is not the owner");
        optionsCompounder.addStrat(strats[0]);

        vm.expectRevert(bytes4(keccak256("OptionsCompounder__OnlyStratAllowed()")));
        optionsCompounder.harvestOTokens(amount, address(exerciser), 1);

        vm.stopPrank();

        /* Admin tries to set different option token */
        vm.startPrank(owner);
        optionsCompounder.setOptionsToken(randomOption);
        vm.stopPrank();
        assertEq(address(optionsCompounder.optionsToken()), randomOption);
    }

    function test_stratsSettings(address randomOption, uint256 amount) public {
        /* Test vectors definition */
        amount = bound(amount, maxUnderlyingAmount / 10, underlyingToken.balanceOf(address(exerciser)) / 10);
        vm.assume(randomOption != address(0));
        address[] memory strats = new address[](2);
        uint256 minAmount = 5;
        strats[0] = makeAddr("strat1");
        strats[1] = makeAddr("strat2");

        fixture_prepareOptionToken(3 * amount, address(optionsCompounder), strats[0], optionsTokenProxy, tokenAdmin);
        fixture_prepareOptionToken(3 * amount, address(optionsCompounder), strats[1], optionsTokenProxy, tokenAdmin);

        vm.startPrank(strats[0]);
        vm.expectRevert(bytes4(keccak256("OptionsCompounder__OnlyStratAllowed()")));
        optionsCompounder.harvestOTokens(amount, address(exerciser), minAmount);
        vm.stopPrank();

        address[] memory receivedStrategies = optionsCompounder.getStrats();
        for (uint256 idx = 0; idx < receivedStrategies.length; idx++) {
            console.log("Strat: %s %s", idx, receivedStrategies[idx]);
        }

        vm.prank(owner);
        optionsCompounder.setStrats(strats);

        receivedStrategies = optionsCompounder.getStrats();
        for (uint256 idx = 0; idx < receivedStrategies.length; idx++) {
            console.log("Strat: %s %s", idx, receivedStrategies[idx]);
        }

        assertEq(receivedStrategies.length, 2);

        vm.prank(strats[0]);
        optionsCompounder.harvestOTokens(amount, address(exerciser), minAmount);

        vm.prank(strats[1]);
        optionsCompounder.harvestOTokens(amount, address(exerciser), minAmount);

        vm.prank(owner);
        optionsCompounder.addStrat(strats[1]);

        receivedStrategies = optionsCompounder.getStrats();
        for (uint256 idx = 0; idx < receivedStrategies.length; idx++) {
            console.log("Strat: %s %s", idx, receivedStrategies[idx]);
        }
        assertEq(receivedStrategies.length, 2);

        address[] memory tmpStrats;
        vm.prank(owner);
        optionsCompounder.setStrats(tmpStrats);

        receivedStrategies = optionsCompounder.getStrats();
        for (uint256 idx = 0; idx < receivedStrategies.length; idx++) {
            console.log("Strat: %s %s", idx, receivedStrategies[idx]);
        }
        assertEq(receivedStrategies.length, 0);

        vm.startPrank(strats[0]);
        vm.expectRevert(bytes4(keccak256("OptionsCompounder__OnlyStratAllowed()")));
        optionsCompounder.harvestOTokens(amount, address(exerciser), minAmount);
        vm.startPrank(strats[1]);
        vm.expectRevert(bytes4(keccak256("OptionsCompounder__OnlyStratAllowed()")));
        optionsCompounder.harvestOTokens(amount, address(exerciser), minAmount);
        vm.stopPrank();

        vm.prank(owner);
        optionsCompounder.addStrat(strats[1]);

        receivedStrategies = optionsCompounder.getStrats();
        for (uint256 idx = 0; idx < receivedStrategies.length; idx++) {
            console.log("Strat: %s %s", idx, receivedStrategies[idx]);
        }
        assertEq(receivedStrategies.length, 1);

        vm.startPrank(strats[1]);
        optionsCompounder.harvestOTokens(amount, address(exerciser), minAmount);
        vm.stopPrank();

        /* Admin tries to set different option token */
        vm.startPrank(owner);
        optionsCompounder.setOptionsToken(randomOption);
        vm.stopPrank();
        assertEq(address(optionsCompounder.optionsToken()), randomOption);
    }

    function test_flashloanNegativeScenario_highTwapValueAndMultiplier(uint256 amount) public {
        /* Test vectors definition */
        amount = bound(amount, maxUnderlyingAmount / 10, underlyingToken.balanceOf(address(exerciser)));

        /* Prepare option tokens - distribute them to the specified strategy
        and approve for spending */
        fixture_prepareOptionToken(amount, address(optionsCompounder), strategies[0], optionsTokenProxy, tokenAdmin);

        /* Decrease option discount in order to make redemption not profitable */
        /* Notice: Multiplier must be higher than denom because of oracle inaccuracy (initTwap) or just change initTwap */
        vm.startPrank(owner);
        exerciser.setMultiplier(9999);
        vm.stopPrank();
        /* Increase TWAP price to make flashloan not profitable */

        vm.startPrank(strategies[0]);
        /* Notice: additional protection is in exerciser: Exercise__SlippageTooHigh */
        vm.expectRevert(bytes4(keccak256("OptionsCompounder__FlashloanNotProfitableEnough()")));
        /* Already approved in fixture_prepareOptionToken */
        optionsCompounder.harvestOTokens(amount, address(exerciser), NON_ZERO_PROFIT);
        vm.stopPrank();
    }

    function test_flashloanNegativeScenario_tooHighMinAmounOfWantExpected(uint256 amount, uint256 minAmountOfPayment) public {
        /* Test vectors definition */
        amount = bound(amount, maxUnderlyingAmount / 10, underlyingToken.balanceOf(address(exerciser)));
        /* Decrease option discount in order to make redemption not profitable */
        /* Notice: Multiplier must be higher than denom because of oracle inaccuracy (initTwap) or just change initTwap */
        vm.startPrank(owner);
        exerciser.setMultiplier(9000);
        vm.stopPrank();
        /* Too high expectation of profit - together with high exerciser multiplier makes flashloan not profitable */
        uint256 paymentAmount = exerciser.getPaymentAmount(amount);

        minAmountOfPayment = bound(minAmountOfPayment, 1e22, UINT256_MAX - paymentAmount);

        /* Prepare option tokens - distribute them to the specified strategy
        and approve for spending */
        fixture_prepareOptionToken(amount, address(optionsCompounder), strategies[0], optionsTokenProxy, tokenAdmin);

        vm.startPrank(strategies[0]);
        /* Notice: additional protection is in exerciser: Exercise__SlippageTooHigh */
        vm.expectRevert(bytes4(keccak256("OptionsCompounder__FlashloanNotProfitableEnough()")));
        /* Already approved in fixture_prepareOptionToken */
        optionsCompounder.harvestOTokens(amount, address(exerciser), minAmountOfPayment);
        vm.stopPrank();
    }

    function test_callExecuteOperationWithoutFlashloanTrigger(uint256 amount, address executor) public {
        /* Test vectors definition */
        amount = bound(amount, maxUnderlyingAmount / 10, underlyingToken.balanceOf(address(exerciser)));

        /* Argument creation */
        address[] memory assets = new address[](1);
        assets[0] = address(paymentToken);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = DiscountExercise(exerciser).getPaymentAmount(amount);
        uint256[] memory premiums = new uint256[](1);
        bytes memory params;

        vm.startPrank(executor);
        /* Assertion */
        vm.expectRevert(bytes4(keccak256("OptionsCompounder__FlashloanNotTriggered()")));
        optionsCompounder.executeOperation(assets, amounts, premiums, msg.sender, params);
        vm.stopPrank();
    }

    function test_harvestCallWithWrongExerciseContract(uint256 amount, address fuzzedExerciser) public {
        /* Test vectors definition */
        amount = bound(amount, maxUnderlyingAmount / 10, underlyingToken.balanceOf(address(exerciser)));

        vm.assume(fuzzedExerciser != address(exerciser));

        /* Prepare option tokens - distribute them to the specified strategy
        and approve for spending */
        fixture_prepareOptionToken(amount, address(optionsCompounder), strategies[0], optionsTokenProxy, tokenAdmin);

        /* Assertion */
        vm.startPrank(strategies[0]);
        vm.expectRevert(bytes4(keccak256("OptionsCompounder__NotExerciseContract()")));
        optionsCompounder.harvestOTokens(amount, fuzzedExerciser, NON_ZERO_PROFIT);
        vm.stopPrank();
    }
}
