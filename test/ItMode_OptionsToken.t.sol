// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IERC20} from "oz/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "oz/proxy/ERC1967/ERC1967Proxy.sol";

import {OptionsToken} from "../src/OptionsToken.sol";
import {DiscountExerciseParams, DiscountExercise, BaseExercise} from "../src/exercise/DiscountExercise.sol";
// import {SwapProps, ExchangeType} from "../src/helpers/SwapHelper.sol";
import {TestERC20} from "./mocks/TestERC20.sol";
import {ThenaOracle} from "../src/oracles/ThenaOracle.sol";
import {MockBalancerTwapOracle} from "./mocks/MockBalancerTwapOracle.sol";

import {ReaperSwapper, MinAmountOutData, MinAmountOutKind, IVeloRouter, ISwapRouter, UniV3SwapData} from "vault-v2/ReaperSwapper.sol";

import "./Common.sol";

contract ModeOptionsTokenTest is Test, Common {
    using FixedPointMathLib for uint256;

    uint256 constant FORK_BLOCK = 9260950;
    string MAINNET_URL = vm.envString("MODE_RPC_URL");
    uint256 constant ORACLE_INIT_TWAP_VALUE = 1e19;

    address[] feeRecipients_;
    uint256[] feeBPS_;

    ThenaOracle oracle;
    MockBalancerTwapOracle balancerTwapOracle;

    function setUp() public {
        /* Common assignments */
        ExchangeType exchangeType = ExchangeType.VeloSolid;
        // nativeToken = IERC20(OP_WETH);
        paymentToken = IERC20(MODE_MODE);
        underlyingToken = IERC20(MODE_WETH);
        // wantToken = IERC20(OP_OP);
        // paymentUnderlyingBpt = OP_OATHV2_ETH_BPT;
        // paymentWantBpt = OP_WETH_OP_USDC_BPT;
        // balancerVault = OP_BEETX_VAULT;
        // swapRouter = ISwapRouter(OP_BEETX_VAULT);
        // univ3Factory = IUniswapV3Factory(OP_UNIV3_FACTORY);
        veloRouter = IVeloRouter(MODE_VELO_ROUTER);
        veloFactory = MODE_VELO_FACTORY;

        /* Setup network */
        uint256 fork = vm.createFork(MAINNET_URL, FORK_BLOCK);
        vm.selectFork(fork);

        // set up accounts
        owner = makeAddr("owner");
        tokenAdmin = makeAddr("tokenAdmin");

        uint256 minAmountToTriggerSwap = 1e5;

        feeRecipients_ = new address[](2);
        feeRecipients_[0] = makeAddr("feeRecipient");
        feeRecipients_[1] = makeAddr("feeRecipient2");

        feeBPS_ = new uint256[](2);
        feeBPS_[0] = 1000; // 10%
        feeBPS_[1] = 9000; // 90%

        address implementation = address(new OptionsToken());
        ERC1967Proxy proxy = new ERC1967Proxy(implementation, "");
        optionsToken = OptionsToken(address(proxy));
        optionsToken.initialize("TIT Call Option Token", "oTIT", tokenAdmin);
        optionsToken.transferOwnership(owner);

        /* Reaper deployment and configuration */
        address[] memory strategists = new address[](1);
        strategists[0] = makeAddr("strategist");
        reaperSwapper = new ReaperSwapper();
        ERC1967Proxy tmpProxy = new ERC1967Proxy(address(reaperSwapper), "");
        reaperSwapper = ReaperSwapper(address(tmpProxy));
        reaperSwapper.initialize(strategists, address(this), address(this));

        fixture_updateSwapperPaths(exchangeType);

        SwapProps memory swapProps = fixture_getSwapProps(exchangeType, 200);

        address[] memory tokens = new address[](2);
        tokens[0] = address(paymentToken);
        tokens[1] = address(underlyingToken);

        balancerTwapOracle = new MockBalancerTwapOracle(tokens);
        console.log(tokens[0], tokens[1]);
        oracle = new ThenaOracle(IThenaPair(MODE_VELO_WETH_MODE_PAIR), address(underlyingToken), owner, ORACLE_SECS, uint128(ORACLE_MIN_PRICE_DENOM));
        exerciser = new DiscountExercise(
            optionsToken,
            owner,
            IERC20(address(paymentToken)),
            underlyingToken,
            oracle,
            PRICE_MULTIPLIER,
            INSTANT_EXIT_FEE,
            minAmountToTriggerSwap,
            feeRecipients_,
            feeBPS_,
            swapProps
        );
        deal(address(underlyingToken), address(exerciser), 1e20 ether);

        /* add exerciser to the list of options */
        vm.startPrank(owner);
        optionsToken.setExerciseContract(address(exerciser), true);
        vm.stopPrank();

        // set up contracts
        balancerTwapOracle.setTwapValue(ORACLE_INIT_TWAP_VALUE);
        paymentToken.approve(address(exerciser), type(uint256).max);
    }

    function test_modeRedeemPositiveScenario(uint256 amount) public {
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

    function test_modeZapPositiveScenario(uint256 amount) public {
        amount = bound(amount, 1e16, 1e18 - 1);
        address recipient = makeAddr("recipient");

        // mint options tokens
        vm.prank(tokenAdmin);
        optionsToken.mint(address(this), amount);

        // mint payment tokens
        uint256 expectedPaymentAmount = amount.mulWadUp(oracle.getPrice().mulDivUp(PRICE_MULTIPLIER, ORACLE_MIN_PRICE_DENOM));
        uint256 discountedUnderlying = amount.mulDivUp(PRICE_MULTIPLIER, 10_000);
        uint256 expectedUnderlyingAmount = discountedUnderlying - discountedUnderlying.mulDivUp(INSTANT_EXIT_FEE, 10_000);
        deal(address(paymentToken), address(this), expectedPaymentAmount);

        // Calculate total fee from zapping
        uint256 calcPaymentAmount = exerciser.getPaymentAmount(amount);
        uint256 totalFee = calcPaymentAmount.mulDivUp(INSTANT_EXIT_FEE, 10_000);

        vm.prank(owner);
        exerciser.setMinAmountToTriggerSwap(discountedUnderlying.mulDivUp(INSTANT_EXIT_FEE, BPS_DENOM) + 1);

        // exercise options tokens
        DiscountExerciseParams memory params =
            DiscountExerciseParams({maxPaymentAmount: expectedPaymentAmount, deadline: type(uint256).max, isInstantExit: true});
        (uint256 paymentAmount,,,) = optionsToken.exercise(amount, recipient, address(exerciser), abi.encode(params));
        console.log("Exercise 1");
        assertEqDecimal(optionsToken.balanceOf(address(this)), 0, 18, "user still has options tokens");
        assertEqDecimal(optionsToken.totalSupply(), 0, 18, "option tokens not burned");

        // verify payment tokens were not transferred
        assertEq(paymentToken.balanceOf(address(this)), expectedPaymentAmount, "user lost payment tokens during instant exit");
        // verify whether distributions not happened
        assertEq(IERC20(paymentToken).balanceOf(feeRecipients_[0]), 0, "fee recipient 1 received payment tokens but shouldn't");
        assertEq(IERC20(paymentToken).balanceOf(feeRecipients_[1]), 0, "fee recipient 2 received payment tokens but shouldn't");
        assertEqDecimal(paymentAmount, 0, 18, "exercise returned wrong value");
        uint256 balanceAfterFirstExercise = underlyingToken.balanceOf(recipient);
        assertApproxEqAbs(balanceAfterFirstExercise, expectedUnderlyingAmount, 1, "recipient got wrong amount of underlying token");

        /*---------- Second call -----------*/
        amount = bound(amount, 1e18, 2e18);
        // mint options tokens
        vm.prank(tokenAdmin);
        optionsToken.mint(address(this), amount);

        // mint payment tokens
        expectedPaymentAmount = amount.mulWadUp(oracle.getPrice().mulDivUp(PRICE_MULTIPLIER, ORACLE_MIN_PRICE_DENOM));
        discountedUnderlying = amount.mulDivUp(PRICE_MULTIPLIER, 10_000);
        expectedUnderlyingAmount = discountedUnderlying - discountedUnderlying.mulDivUp(INSTANT_EXIT_FEE, 10_000);
        deal(address(paymentToken), address(this), expectedPaymentAmount);

        (paymentAmount,,,) = optionsToken.exercise(amount, recipient, address(exerciser), abi.encode(params));

        // verify options tokens were transferred
        console.log("Exercise 2");
        assertEqDecimal(optionsToken.balanceOf(address(this)), 0, 18, "user still has options tokens");
        assertEqDecimal(optionsToken.totalSupply(), 0, 18, "option tokens not burned");

        // verify payment tokens were not transferred
        assertEq(paymentToken.balanceOf(address(this)), expectedPaymentAmount, "user lost payment tokens during instant exit");

        // verify fee is distributed
        calcPaymentAmount = exerciser.getPaymentAmount(amount);
        totalFee += calcPaymentAmount.mulDivUp(INSTANT_EXIT_FEE, 10_000);
        uint256 fee1 = totalFee.mulDivDown(feeBPS_[0], 10_000);
        uint256 fee2 = totalFee - fee1;
        console.log("paymentFee1: ", fee1);
        console.log("paymentFee2: ", fee2);
        assertApproxEqRel(IERC20(paymentToken).balanceOf(feeRecipients_[0]), fee1, 5e16, "fee recipient 1 didn't receive payment tokens");
        assertApproxEqRel(IERC20(paymentToken).balanceOf(feeRecipients_[1]), fee2, 5e16, "fee recipient 2 didn't receive payment tokens");
        assertEqDecimal(paymentAmount, 0, 18, "exercise returned wrong value");
        assertApproxEqAbs(
            underlyingToken.balanceOf(recipient),
            expectedUnderlyingAmount + balanceAfterFirstExercise,
            1,
            "Recipient got wrong amount of underlying token"
        );
    }

    function test_modeExerciseNotOToken(uint256 amount) public {
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

    function test_modeExerciseNotExerciseContract(uint256 amount) public {
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
}
