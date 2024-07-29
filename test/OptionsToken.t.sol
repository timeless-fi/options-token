// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IERC20} from "oz/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "oz/proxy/ERC1967/ERC1967Proxy.sol";

import {OptionsToken} from "../src/OptionsToken.sol";
import {DiscountExerciseParams, DiscountExercise, BaseExercise, SwapProps, ExchangeType} from "../src/exercise/DiscountExercise.sol";
import {TestERC20} from "./mocks/TestERC20.sol";
import {IOracle} from "../src/interfaces/IOracle.sol";
import {BalancerOracle} from "../src/oracles/BalancerOracle.sol";
import {MockBalancerTwapOracle} from "./mocks/MockBalancerTwapOracle.sol";

import {ReaperSwapperMock} from "./mocks/ReaperSwapperMock.sol";

contract OptionsTokenTest is Test {
    using FixedPointMathLib for uint256;

    uint16 constant PRICE_MULTIPLIER = 5000; // 0.5
    uint56 constant ORACLE_SECS = 30 minutes;
    uint56 constant ORACLE_AGO = 2 minutes;
    uint128 constant ORACLE_MIN_PRICE = 1e17;
    uint56 constant ORACLE_LARGEST_SAFETY_WINDOW = 24 hours;
    uint256 constant ORACLE_INIT_TWAP_VALUE = 1e19;
    uint256 constant ORACLE_MIN_PRICE_DENOM = 10000;
    uint256 constant MAX_SUPPLY = 1e27; // the max supply of the options token & the underlying token
    uint256 constant INSTANT_EXIT_FEE = 500;
    uint256 constant BPS_DENOM = 10_000;

    address owner;
    address tokenAdmin;
    address[] feeRecipients_;
    uint256[] feeBPS_;

    OptionsToken optionsToken;
    DiscountExercise exerciser;
    IOracle oracle;
    MockBalancerTwapOracle balancerTwapOracle;
    TestERC20 paymentToken;
    address underlyingToken;
    ReaperSwapperMock reaperSwapper;

    function setUp() public {
        // set up accounts
        owner = makeAddr("owner");
        tokenAdmin = makeAddr("tokenAdmin");

        feeRecipients_ = new address[](2);
        feeRecipients_[0] = makeAddr("feeRecipient");
        feeRecipients_[1] = makeAddr("feeRecipient2");

        feeBPS_ = new uint256[](2);
        feeBPS_[0] = 1000; // 10%
        feeBPS_[1] = 9000; // 90%

        // deploy contracts
        paymentToken = new TestERC20();
        underlyingToken = address(new TestERC20());

        address implementation = address(new OptionsToken());
        ERC1967Proxy proxy = new ERC1967Proxy(implementation, "");
        optionsToken = OptionsToken(address(proxy));
        optionsToken.initialize("TIT Call Option Token", "oTIT", tokenAdmin);
        optionsToken.transferOwnership(owner);

        /* Reaper deployment and configuration */
        uint256 slippage = 500; // 5%
        uint256 minAmountToTriggerSwap = 1e5;

        address[] memory tokens = new address[](2);
        tokens[0] = address(paymentToken);
        tokens[1] = underlyingToken;

        balancerTwapOracle = new MockBalancerTwapOracle(tokens);
        console.log(tokens[0], tokens[1]);
        oracle = IOracle(new BalancerOracle(balancerTwapOracle, underlyingToken, owner, ORACLE_SECS, ORACLE_AGO, ORACLE_MIN_PRICE));

        reaperSwapper = new ReaperSwapperMock(oracle, address(underlyingToken), address(paymentToken));
        deal(underlyingToken, address(reaperSwapper), 1e27);
        deal(address(paymentToken), address(reaperSwapper), 1e27);

        SwapProps memory swapProps = SwapProps(address(reaperSwapper), address(reaperSwapper), ExchangeType.Bal, slippage);

        exerciser = new DiscountExercise(
            optionsToken,
            owner,
            IERC20(address(paymentToken)),
            IERC20(underlyingToken),
            oracle,
            PRICE_MULTIPLIER,
            INSTANT_EXIT_FEE,
            minAmountToTriggerSwap,
            feeRecipients_,
            feeBPS_,
            swapProps
        );
        deal(underlyingToken, address(exerciser), 1e27);

        // add exerciser to the list of options
        vm.startPrank(owner);
        optionsToken.setExerciseContract(address(exerciser), true);
        vm.stopPrank();

        // set up contracts
        balancerTwapOracle.setTwapValue(ORACLE_INIT_TWAP_VALUE);
        paymentToken.approve(address(exerciser), type(uint256).max);
    }

    function test_onlyTokenAdminCanMint(uint256 amount, address hacker) public {
        vm.assume(hacker != tokenAdmin);

        // try minting as non token admin
        vm.startPrank(hacker);
        vm.expectRevert(OptionsToken.OptionsToken__NotTokenAdmin.selector);
        optionsToken.mint(address(this), amount);
        vm.stopPrank();

        // mint as token admin
        vm.prank(tokenAdmin);
        optionsToken.mint(address(this), amount);

        // verify balance
        assertEqDecimal(optionsToken.balanceOf(address(this)), amount, 18);
    }

    function test_redeemPositiveScenario(uint256 amount) public {
        amount = bound(amount, 100, MAX_SUPPLY);
        address recipient = makeAddr("recipient");

        // mint options tokens
        vm.prank(tokenAdmin);
        optionsToken.mint(address(this), amount);

        // mint payment tokens
        uint256 expectedPaymentAmount = amount.mulWadUp(oracle.getPrice().mulDivUp(PRICE_MULTIPLIER, ORACLE_MIN_PRICE_DENOM));
        deal(address(paymentToken), address(this), expectedPaymentAmount);

        // exercise options tokens
        DiscountExerciseParams memory params =
            DiscountExerciseParams({maxPaymentAmount: expectedPaymentAmount, deadline: type(uint256).max, isInstantExit: false});
        (uint256 paymentAmount,,,) = optionsToken.exercise(amount, recipient, address(exerciser), abi.encode(params));

        // verify options tokens were transferred
        assertEqDecimal(optionsToken.balanceOf(address(this)), 0, 18, "user still has options tokens");
        assertEqDecimal(optionsToken.totalSupply(), 0, 18, "option tokens not burned");

        // verify payment tokens were transferred
        assertEqDecimal(paymentToken.balanceOf(address(this)), 0, 18, "user still has payment tokens");
        uint256 paymentFee1 = expectedPaymentAmount.mulDivDown(feeBPS_[0], 10000);
        uint256 paymentFee2 = expectedPaymentAmount - paymentFee1;
        assertEqDecimal(paymentToken.balanceOf(feeRecipients_[0]), paymentFee1, 18, "fee recipient 1 didn't receive payment tokens");
        assertEqDecimal(paymentToken.balanceOf(feeRecipients_[1]), paymentFee2, 18, "fee recipient 2 didn't receive payment tokens");
        assertEqDecimal(expectedPaymentAmount, paymentAmount, 18, "exercise returned wrong value");
    }

    function test_zapPositiveScenario(uint256 amount) public {
        amount = bound(amount, 1e16, 1e22);
        address recipient = makeAddr("recipient");

        // mint options tokens
        vm.prank(tokenAdmin);
        optionsToken.mint(address(this), amount);

        // mint payment tokens
        uint256 expectedPaymentAmount = amount.mulWadUp(ORACLE_INIT_TWAP_VALUE.mulDivUp(PRICE_MULTIPLIER, ORACLE_MIN_PRICE_DENOM));
        uint256 discountedUnderlying = amount.mulDivUp(PRICE_MULTIPLIER, 10_000);
        uint256 expectedUnderlyingAmount = discountedUnderlying - discountedUnderlying.mulDivUp(INSTANT_EXIT_FEE, 10_000);
        deal(address(paymentToken), address(this), expectedPaymentAmount);
        console.log("discountedUnderlying:", discountedUnderlying);
        console.log("expectedUnderlyingAmount:", expectedUnderlyingAmount);

        // exercise options tokens
        DiscountExerciseParams memory params =
            DiscountExerciseParams({maxPaymentAmount: expectedPaymentAmount, deadline: type(uint256).max, isInstantExit: true});
        (uint256 paymentAmount,,,) = optionsToken.exercise(amount, recipient, address(exerciser), abi.encode(params));

        // verify options tokens were transferred
        assertEqDecimal(optionsToken.balanceOf(address(this)), 0, 18, "user still has options tokens");
        assertEqDecimal(optionsToken.totalSupply(), 0, 18, "option tokens not burned");

        // verify payment tokens were transferred
        assertEq(paymentToken.balanceOf(address(this)), expectedPaymentAmount, "user lost payment tokens during instant exit");
        uint256 calcPaymentAmount = exerciser.getPaymentAmount(amount);
        uint256 totalFee = calcPaymentAmount.mulDivUp(INSTANT_EXIT_FEE, 10_000);
        uint256 fee1 = totalFee.mulDivDown(feeBPS_[0], 10_000);
        uint256 fee2 = totalFee - fee1;
        console.log("paymentFee1: ", fee1);
        console.log("paymentFee2: ", fee2);
        assertApproxEqRel(paymentToken.balanceOf(feeRecipients_[0]), fee1, 10e16, "fee recipient 1 didn't receive payment tokens");
        assertApproxEqRel(paymentToken.balanceOf(feeRecipients_[1]), fee2, 10e16, "fee recipient 2 didn't receive payment tokens");
        assertEqDecimal(paymentAmount, 0, 18, "exercise returned wrong value");
        assertApproxEqAbs(IERC20(underlyingToken).balanceOf(recipient), expectedUnderlyingAmount, 1, "Recipient got wrong amount of underlying token");
    }

    function test_exerciseMinPrice(uint256 amount) public {
        amount = bound(amount, 1, MAX_SUPPLY);
        address recipient = makeAddr("recipient");

        // mint options tokens
        vm.prank(tokenAdmin);
        optionsToken.mint(address(this), amount);

        // set TWAP value such that the strike price is below the oracle's minPrice value
        balancerTwapOracle.setTwapValue(ORACLE_MIN_PRICE - 1);

        // mint payment tokens
        uint256 expectedPaymentAmount = amount.mulWadUp(ORACLE_MIN_PRICE);
        deal(address(paymentToken), address(this), expectedPaymentAmount);

        // exercise options tokens
        DiscountExerciseParams memory params =
            DiscountExerciseParams({maxPaymentAmount: expectedPaymentAmount, deadline: type(uint256).max, isInstantExit: false});
        vm.expectRevert(bytes4(keccak256("BalancerOracle__BelowMinPrice()")));
        optionsToken.exercise(amount, recipient, address(exerciser), abi.encode(params));
    }

    function test_priceMultiplier(uint256 amount, uint256 multiplier) public {
        amount = bound(amount, 1, MAX_SUPPLY / 2);

        vm.prank(owner);
        exerciser.setMultiplier(10000); // full price

        // mint options tokens
        vm.prank(tokenAdmin);
        optionsToken.mint(address(this), amount * 2);

        // mint payment tokens
        uint256 expectedPaymentAmount = amount.mulWadUp(ORACLE_INIT_TWAP_VALUE);
        deal(address(paymentToken), address(this), expectedPaymentAmount);

        // exercise options tokens
        DiscountExerciseParams memory params =
            DiscountExerciseParams({maxPaymentAmount: expectedPaymentAmount, deadline: type(uint256).max, isInstantExit: false});
        (uint256 paidAmount,,,) = optionsToken.exercise(amount, address(this), address(exerciser), abi.encode(params));

        // update multiplier
        multiplier = bound(multiplier, 1000, 20000);
        vm.prank(owner);
        exerciser.setMultiplier(multiplier);

        // exercise options tokens
        uint256 newPrice = oracle.getPrice().mulDivUp(multiplier, 10000);
        uint256 newExpectedPaymentAmount = amount.mulWadUp(newPrice);
        params.maxPaymentAmount = newExpectedPaymentAmount;

        deal(address(paymentToken), address(this), newExpectedPaymentAmount);
        (uint256 newPaidAmount,,,) = optionsToken.exercise(amount, address(this), address(exerciser), abi.encode(params));
        // verify payment tokens were transferred
        assertEqDecimal(paymentToken.balanceOf(address(this)), 0, 18, "user still has payment tokens");
        assertEq(newPaidAmount, paidAmount.mulDivUp(multiplier, 10000), "incorrect discount");
    }

    function test_exerciseHighSlippage(uint256 amount, address recipient) public {
        amount = bound(amount, 1, MAX_SUPPLY);
        vm.assume(recipient != address(0));

        // mint options tokens
        vm.prank(tokenAdmin);
        optionsToken.mint(address(this), amount);

        // mint payment tokens
        uint256 expectedPaymentAmount = amount.mulWadUp(ORACLE_INIT_TWAP_VALUE.mulDivUp(PRICE_MULTIPLIER, ORACLE_MIN_PRICE_DENOM));
        deal(address(paymentToken), address(this), expectedPaymentAmount);

        // exercise options tokens which should fail
        DiscountExerciseParams memory params =
            DiscountExerciseParams({maxPaymentAmount: expectedPaymentAmount - 1, deadline: type(uint256).max, isInstantExit: false});
        vm.expectRevert(DiscountExercise.Exercise__SlippageTooHigh.selector);
        optionsToken.exercise(amount, recipient, address(exerciser), abi.encode(params));
    }

    // function test_exerciseTwapOracleNotReady(uint256 amount, address recipient) public {
    //     amount = bound(amount, 1, MAX_SUPPLY);

    //     // mint options tokens
    //     vm.prank(tokenAdmin);
    //     optionsToken.mint(address(this), amount);

    //     // mint payment tokens
    //     uint256 expectedPaymentAmount = amount.mulWadUp(ORACLE_INIT_TWAP_VALUE.mulDivUp(PRICE_MULTIPLIER, ORACLE_MIN_PRICE_DENOM));
    //     deal(address(paymentToken), address(this), expectedPaymentAmount);

    //     // update oracle params
    //     // such that the TWAP window becomes (block.timestamp - ORACLE_LARGEST_SAFETY_WINDOW - ORACLE_SECS, block.timestamp - ORACLE_LARGEST_SAFETY_WINDOW]
    //     // which is outside of the largest safety window
    //     // vm.prank(owner);
    //     // oracle.setParams(ORACLE_SECS, ORACLE_LARGEST_SAFETY_WINDOW, ORACLE_MIN_PRICE);

    //     // exercise options tokens which should fail
    //     DiscountExerciseParams memory params =
    //         DiscountExerciseParams({maxPaymentAmount: expectedPaymentAmount, deadline: type(uint256).max, isInstantExit: false});
    //     vm.expectRevert(ThenaOracle.ThenaOracle__TWAPOracleNotReady.selector);
    //     optionsToken.exercise(amount, recipient, address(exerciser), abi.encode(params));
    // }

    function test_exercisePastDeadline(uint256 amount, uint256 deadline) public {
        amount = bound(amount, 0, MAX_SUPPLY);
        deadline = bound(deadline, 0, block.timestamp - 1);
        address recipient = makeAddr("recipient");

        // mint options tokens
        vm.prank(tokenAdmin);
        optionsToken.mint(address(this), amount);

        // mint payment tokens
        uint256 expectedPaymentAmount = amount.mulWadUp(ORACLE_INIT_TWAP_VALUE.mulDivUp(PRICE_MULTIPLIER, ORACLE_MIN_PRICE_DENOM));
        deal(address(paymentToken), address(this), expectedPaymentAmount);

        // exercise options tokens
        DiscountExerciseParams memory params =
            DiscountExerciseParams({maxPaymentAmount: expectedPaymentAmount, deadline: deadline, isInstantExit: false});
        if (amount != 0) {
            vm.expectRevert(DiscountExercise.Exercise__PastDeadline.selector);
        }
        optionsToken.exercise(amount, recipient, address(exerciser), abi.encode(params));
    }

    function test_exerciseNotOToken(uint256 amount) public {
        amount = bound(amount, 0, MAX_SUPPLY);
        address recipient = makeAddr("recipient");

        // mint options tokens
        vm.prank(tokenAdmin);
        optionsToken.mint(address(this), amount);

        uint256 expectedPaymentAmount = amount.mulWadUp(ORACLE_INIT_TWAP_VALUE.mulDivUp(PRICE_MULTIPLIER, ORACLE_MIN_PRICE_DENOM));
        deal(address(paymentToken), address(this), expectedPaymentAmount);

        // exercise options tokens which should fail
        DiscountExerciseParams memory params =
            DiscountExerciseParams({maxPaymentAmount: expectedPaymentAmount, deadline: type(uint256).max, isInstantExit: false});
        vm.expectRevert(BaseExercise.Exercise__NotOToken.selector);
        exerciser.exercise(address(this), amount, recipient, abi.encode(params));
    }

    function test_exerciseNotExerciseContract(uint256 amount) public {
        amount = bound(amount, 1, MAX_SUPPLY);
        address recipient = makeAddr("recipient");

        // mint options tokens
        vm.prank(tokenAdmin);
        optionsToken.mint(address(this), amount);

        // set option inactive
        vm.prank(owner);
        optionsToken.setExerciseContract(address(exerciser), false);

        // mint payment tokens
        uint256 expectedPaymentAmount = amount.mulWadUp(ORACLE_INIT_TWAP_VALUE.mulDivUp(PRICE_MULTIPLIER, ORACLE_MIN_PRICE_DENOM));
        deal(address(paymentToken), address(this), expectedPaymentAmount);

        // exercise options tokens which should fail
        DiscountExerciseParams memory params =
            DiscountExerciseParams({maxPaymentAmount: expectedPaymentAmount, deadline: type(uint256).max, isInstantExit: false});
        vm.expectRevert(OptionsToken.OptionsToken__NotExerciseContract.selector);
        optionsToken.exercise(amount, recipient, address(exerciser), abi.encode(params));
    }

    function test_exerciseWhenPaused(uint256 amount) public {
        amount = bound(amount, 100, 1 ether);
        address recipient = makeAddr("recipient");

        // mint options tokens
        vm.prank(tokenAdmin);
        optionsToken.mint(address(this), 3 * amount);

        // mint payment tokens
        uint256 expectedPaymentAmount = 3 * amount.mulWadUp(oracle.getPrice().mulDivUp(PRICE_MULTIPLIER, ORACLE_MIN_PRICE_DENOM));
        deal(address(paymentToken), address(this), expectedPaymentAmount);

        // exercise options tokens
        DiscountExerciseParams memory params =
            DiscountExerciseParams({maxPaymentAmount: expectedPaymentAmount, deadline: type(uint256).max, isInstantExit: false});
        optionsToken.exercise(amount, recipient, address(exerciser), abi.encode(params));

        /* Only owner can pause */
        vm.startPrank(recipient);
        vm.expectRevert(bytes("UNAUTHORIZED")); // Ownable: caller is not the owner
        exerciser.pause();
        vm.stopPrank();

        vm.prank(owner);
        exerciser.pause();
        vm.expectRevert(bytes("Pausable: paused"));
        optionsToken.exercise(amount, recipient, address(exerciser), abi.encode(params));

        vm.prank(owner);
        exerciser.unpause();
        optionsToken.exercise(amount, recipient, address(exerciser), abi.encode(params));
    }

    function test_oTokenWhenPaused(uint256 amount) public {
        amount = bound(amount, 100, 1 ether);
        address recipient = makeAddr("recipient");

        // mint options tokens
        vm.prank(tokenAdmin);
        optionsToken.mint(address(this), 3 * amount);

        // mint payment tokens
        uint256 expectedPaymentAmount = 3 * amount.mulWadUp(oracle.getPrice().mulDivUp(PRICE_MULTIPLIER, ORACLE_MIN_PRICE_DENOM));
        deal(address(paymentToken), address(this), expectedPaymentAmount);

        // exercise options tokens
        DiscountExerciseParams memory params =
            DiscountExerciseParams({maxPaymentAmount: expectedPaymentAmount, deadline: type(uint256).max, isInstantExit: false});
        optionsToken.exercise(amount, recipient, address(exerciser), abi.encode(params));

        /* Only owner can pause */
        vm.startPrank(recipient);
        vm.expectRevert(bytes("Ownable: caller is not the owner")); // Ownable: caller is not the owner
        optionsToken.pause();
        vm.stopPrank();

        vm.prank(owner);
        optionsToken.pause();
        vm.expectRevert(bytes("Pausable: paused"));
        optionsToken.exercise(amount, recipient, address(exerciser), abi.encode(params));

        vm.prank(owner);
        optionsToken.unpause();
        optionsToken.exercise(amount, recipient, address(exerciser), abi.encode(params));
    }

    function test_exerciserConfigAccesses() public {
        uint256 slippage = 555; // 5.55%
        address[] memory tokens = new address[](2);
        tokens[0] = address(paymentToken);
        tokens[1] = underlyingToken;
        balancerTwapOracle = new MockBalancerTwapOracle(tokens);
        oracle = IOracle(new BalancerOracle(balancerTwapOracle, underlyingToken, owner, ORACLE_SECS, ORACLE_AGO, ORACLE_MIN_PRICE));

        reaperSwapper = new ReaperSwapperMock(oracle, address(underlyingToken), address(paymentToken));
        SwapProps memory swapProps = SwapProps(address(reaperSwapper), address(reaperSwapper), ExchangeType.Bal, slippage);

        vm.expectRevert(bytes("UNAUTHORIZED"));
        exerciser.setSwapProps(swapProps);

        vm.prank(owner);
        exerciser.setSwapProps(swapProps);

        vm.expectRevert(bytes("UNAUTHORIZED"));
        exerciser.setOracle(oracle);

        vm.prank(owner);
        exerciser.setOracle(oracle);

        vm.expectRevert(bytes("UNAUTHORIZED"));
        exerciser.setMultiplier(3333);

        vm.prank(owner);
        exerciser.setMultiplier(3333);

        vm.expectRevert(bytes("UNAUTHORIZED"));
        exerciser.setInstantExitFee(1444);

        vm.prank(owner);
        exerciser.setInstantExitFee(1444);

        vm.expectRevert(bytes("UNAUTHORIZED"));
        exerciser.setMinAmountToTriggerSwap(1e16);

        vm.prank(owner);
        exerciser.setMinAmountToTriggerSwap(1e16);
    }

    function test_zapWhenExerciseUnderfunded(uint256 amount) public {
        amount = bound(amount, 1e16, 1e22);
        address recipient = makeAddr("recipient");

        uint256 remainingAmount = 4e15;

        // mint options tokens
        vm.prank(tokenAdmin);
        optionsToken.mint(address(this), amount);

        // mint payment tokens
        uint256 expectedPaymentAmount = amount.mulWadUp(ORACLE_INIT_TWAP_VALUE.mulDivUp(PRICE_MULTIPLIER, ORACLE_MIN_PRICE_DENOM));
        uint256 discountedUnderlying = amount.mulDivUp(PRICE_MULTIPLIER, 10_000);
        uint256 expectedUnderlyingAmount = discountedUnderlying - discountedUnderlying.mulDivUp(INSTANT_EXIT_FEE, 10_000);
        deal(address(paymentToken), address(this), expectedPaymentAmount);
        console.log("discountedUnderlying:", discountedUnderlying);
        console.log("expectedUnderlyingAmount:", expectedUnderlyingAmount);
        uint256 calcPaymentAmount = exerciser.getPaymentAmount(amount);
        uint256 totalFee = calcPaymentAmount.mulDivUp(INSTANT_EXIT_FEE, 10_000);
        uint256 fee1 = totalFee.mulDivDown(feeBPS_[0], 10_000);
        uint256 fee2 = totalFee - fee1;
        console.log("expected paymentFee1: ", fee1);
        console.log("expected paymentFee2: ", fee2);

        // Simulate sitiation when exerciser has less underlying amount than expected from exercise action
        vm.prank(address(exerciser));
        // IERC20(underlyingToken).transfer(address(this), 1e27 - (discountedUnderlying - 1));
        IERC20(underlyingToken).transfer(address(this), 1e27 - remainingAmount);
        console.log("Balance of exerciser:", IERC20(underlyingToken).balanceOf(address(exerciser)));

        // exercise options tokens
        DiscountExerciseParams memory params =
            DiscountExerciseParams({maxPaymentAmount: expectedPaymentAmount, deadline: type(uint256).max, isInstantExit: true});
        (uint256 paymentAmount,,,) = optionsToken.exercise(amount, recipient, address(exerciser), abi.encode(params));

        // verify options tokens were transferred
        assertEqDecimal(optionsToken.balanceOf(address(this)), 0, 18, "user still has options tokens");
        assertEqDecimal(optionsToken.totalSupply(), 0, 18, "option tokens not burned");

        // verify payment tokens were transferred
        assertEq(paymentToken.balanceOf(address(this)), expectedPaymentAmount, "user lost payment tokens during instant exit");

        assertEq(paymentToken.balanceOf(feeRecipients_[0]), 0, "fee recipient 1 didn't receive payment tokens");
        assertEq(paymentToken.balanceOf(feeRecipients_[1]), 0, "fee recipient 2 didn't receive payment tokens");
        assertEqDecimal(paymentAmount, 0, 18, "exercise returned wrong value");
        assertEq(IERC20(underlyingToken).balanceOf(recipient), remainingAmount, "Recipient got wrong amount of underlying token");
    }

    function test_modeZapRedeemWithDifferentMultipliers(uint256 multiplier) public {
        multiplier = bound(multiplier, BPS_DENOM / 10, BPS_DENOM - 1);
        // multiplier = 8000;
        uint256 amount = 1000e18;

        address recipient = makeAddr("recipient");

        // mint options tokens
        vm.prank(tokenAdmin);
        optionsToken.mint(address(this), 2 * amount);

        vm.prank(owner);
        exerciser.setMultiplier(multiplier);
        uint256 expectedPaymentAmount = amount.mulWadUp(ORACLE_INIT_TWAP_VALUE) * 4;
        deal(address(paymentToken), address(this), expectedPaymentAmount);

        uint256 underlyingBalance =
            IERC20(underlyingToken).balanceOf(address(this)) + paymentToken.balanceOf(address(this)).divWadUp(oracle.getPrice());
        console.log("Price: ", oracle.getPrice());
        console.log("Balance before: ", underlyingBalance);
        console.log("Underlying amount before: ", IERC20(underlyingToken).balanceOf(address(this)));

        // exercise options tokens -> redeem
        DiscountExerciseParams memory params =
            DiscountExerciseParams({maxPaymentAmount: expectedPaymentAmount, deadline: type(uint256).max, isInstantExit: false});
        (uint256 paymentAmount,,,) = optionsToken.exercise(amount, address(this), address(exerciser), abi.encode(params));

        uint256 underlyingBalanceAfterRedeem =
            IERC20(underlyingToken).balanceOf(address(this)) + paymentToken.balanceOf(address(this)).divWadUp(oracle.getPrice());
        console.log("Price: ", oracle.getPrice());
        console.log("Underlying amount after redeem: ", IERC20(underlyingToken).balanceOf(address(this)));
        console.log("Balance after redeem: ", underlyingBalanceAfterRedeem);

        assertGt(underlyingBalanceAfterRedeem, underlyingBalance, "Redeem not profitable");
        uint256 redeemProfit = underlyingBalanceAfterRedeem - underlyingBalance;

        // exercise options tokens -> zap
        params = DiscountExerciseParams({maxPaymentAmount: expectedPaymentAmount, deadline: type(uint256).max, isInstantExit: true});
        (paymentAmount,,,) = optionsToken.exercise(amount, address(this), address(exerciser), abi.encode(params));

        uint256 underlyingBalanceAfterZap =
            IERC20(underlyingToken).balanceOf(address(this)) + paymentToken.balanceOf(address(this)).divWadUp(oracle.getPrice());
        console.log("Price: ", oracle.getPrice());
        console.log("Underlying amount after zap: ", IERC20(underlyingToken).balanceOf(address(this)));
        console.log("Balance after zap: ", underlyingBalanceAfterZap);

        assertGt(underlyingBalanceAfterZap, underlyingBalanceAfterRedeem, "Zap not profitable");
        uint256 zapProfit = underlyingBalanceAfterZap - underlyingBalanceAfterRedeem;

        assertGt(redeemProfit, zapProfit, "Profits from zap is greater than profits from redeem");

        assertEq(redeemProfit - redeemProfit.mulDivUp(INSTANT_EXIT_FEE, BPS_DENOM), zapProfit, "Zap profit is different than redeem profit minus fee");
    }
}
