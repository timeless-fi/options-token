// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.13;

import "./Common.sol";

// import {ReaperStrategySonne} from "./strategies/ReaperStrategySonne.sol";
// import {ReaperStrategyGranary} from "./strategies/ReaperStrategyGranary.sol";
import {CErc20I} from "./strategies/interfaces/CErc20I.sol";
import {OptionsToken} from "optionsToken/src/OptionsToken.sol";
import {Helper} from "./mocks/HelperFunctions.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IERC20} from "oz/token/ERC20/IERC20.sol";
import {IAToken} from "./strategies/interfaces/IAToken.sol";
import {IOracle} from "optionsToken/src/interfaces/IOracle.sol";
import {OptionsCompounder} from "../src/OptionsCompounder.sol";
import {MockedLendingPool} from "../test/mocks/MockedStrategy.sol";

contract OptionsTokenTest is Common {
    using FixedPointMathLib for uint256;

    /* Variable assignment (depends on chain) */
    uint256 FORK_BLOCK = 115072010;
    string MAINNET_URL = vm.envString("OP_RPC_URL_MAINNET");

    /* Contract variables */
    OptionsCompounder optionsCompounder;
    IOracle underlyingPaymentOracle;
    UniswapV3Oracle paymentWantOracle;
    address strategy = makeAddr("strategy");
    Helper helper;
    uint256 initTwap;
    IOracle oracle;

    /* Functions */
    function setUp() public {
        /* Common assignments */
        ExchangeType exchangeType = ExchangeType.Bal;
        nativeToken = IERC20(OP_WETH);
        paymentToken = nativeToken;
        underlyingToken = IERC20(OP_OATHV2);
        wantToken = IERC20(OP_OP);
        paymentUnderlyingBpt = OP_OATHV2_ETH_BPT;
        paymentWantBpt = OP_WETH_OP_USDC_BPT;
        balancerVault = OP_BEETX_VAULT;
        swapRouter = ISwapRouter(OP_BEETX_VAULT);
        univ3Factory = IUniswapV3Factory(OP_UNIV3_FACTORY);

        /* Setup network */
        uint256 optimismFork = vm.createFork(MAINNET_URL, FORK_BLOCK);
        vm.selectFork(optimismFork);

        /* Setup accounts */
        fixture_setupAccountsAndFees(2500, 7500);
        vm.deal(address(this), AMOUNT * 3);
        vm.deal(owner, AMOUNT * 3);

        /* Setup roles */
        address[] memory strategists = new address[](1);
        // address[] memory multisigRoles = new address[](3);
        // address[] memory keepers = new address[](1);
        strategists[0] = strategist;
        // multisigRoles[0] = management1;
        // multisigRoles[1] = management2;
        // multisigRoles[2] = management3;
        // keepers[0] = keeper;

        /* Variables */
        SwapProps memory swapProps = fixture_getSwapProps(exchangeType, 500);

        /**** Contract deployments and configurations ****/
        helper = new Helper();

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
        optionsTokenProxy.initialize(
            "TIT Call Option Token",
            "oTIT",
            tokenAdmin
        );
        /* Exercise contract deployment */
        exerciser = new DiscountExercise(
            optionsTokenProxy,
            owner,
            paymentToken,
            underlyingToken,
            oracle,
            PRICE_MULTIPLIER,
            treasuries,
            feeBPS
        );
        /* Add exerciser to the list of options */
        optionsTokenProxy.setExerciseContract(address(exerciser), true);

        /* Deployment */
        optionsCompounder = new OptionsCompounder();
        tmpProxy = new ERC1967Proxy(address(optionsCompounder), "");
        optionsCompounder = OptionsCompounder(address(tmpProxy));
        MockedLendingPool addressProviderAndLendingPoolMock = new MockedLendingPool(
                address(optionsCompounder)
            );
        optionsCompounder.initialize(
            address(optionsTokenProxy),
            address(addressProviderAndLendingPoolMock),
            address(reaperSwapper),
            swapProps,
            oracle
        );
        vm.stopPrank();

        /* Prepare EOA and contracts for tests */
        helper.wrapEth{value: AMOUNT * 2}(address(nativeToken));

        MinAmountOutData memory minAmountOutData = MinAmountOutData(
            MinAmountOutKind.Absolute,
            0
        );
        paymentToken.approve(address(reaperSwapper), AMOUNT);
        reaperSwapper.swapBal(
            address(paymentToken),
            address(underlyingToken),
            AMOUNT,
            minAmountOutData,
            OP_BEETX_VAULT
        );
        uint256 underlyingBalance = underlyingToken.balanceOf(address(this));
        paymentToken.transfer(
            address(addressProviderAndLendingPoolMock),
            paymentToken.balanceOf(address(this))
        );
        initTwap = AMOUNT.mulDivUp(1e18, underlyingBalance); // Inaccurate solution but it is not crucial to have real accurate oracle price
        underlyingToken.transfer(address(exerciser), underlyingBalance);

        /* Set up contracts - added here to calculate initTwap after swap */
        underlyingPaymentMock.setTwapValue(initTwap);
        paymentToken.approve(address(exerciser), type(uint256).max);
    }

    function test_flashloanPositiveScenario(uint256 amount) public {
        /* Test vectors definition */
        amount = bound(
            amount,
            MIN_OATH_FOR_FUZZING,
            underlyingToken.balanceOf(address(exerciser))
        );
        uint256 minAmount = 200;
        /* Prepare option tokens - distribute them to the specified strategy
    and approve for spending */
        fixture_prepareOptionToken(
            amount,
            address(optionsCompounder),
            strategy,
            optionsTokenProxy,
            tokenAdmin
        );

        /* Check balances before compounding */
        uint256 paymentTokenBalance = paymentToken.balanceOf(
            address(optionsCompounder)
        );

        vm.startPrank(strategy);
        /* already approved in fixture_prepareOptionToken */
        optionsCompounder.harvestOTokens(
            amount,
            address(exerciser),
            NON_ZERO_PROFIT
        );
        vm.stopPrank();

        /* Assertions */
        assertGt(
            paymentToken.balanceOf(strategy),
            paymentTokenBalance + minAmount,
            "Gain not greater than 0"
        );
        assertEq(
            optionsTokenProxy.balanceOf(address(optionsCompounder)),
            0,
            "Options token balance in compounder is 0"
        );
        assertEq(
            paymentToken.balanceOf(address(optionsCompounder)),
            0,
            "Payment token balance in compounder is 0"
        );
    }

    function test_accessControlFunctionsChecks(
        address hacker,
        address randomOption,
        uint256 amount
    ) public {
        /* Test vectors definition */
        amount = bound(
            amount,
            MIN_OATH_FOR_FUZZING,
            underlyingToken.balanceOf(address(exerciser))
        );
        vm.assume(randomOption != address(0));
        vm.assume(hacker != owner);
        SwapProps memory swapProps = SwapProps(
            address(swapRouter),
            ExchangeType.UniV3,
            200
        );
        /* Hacker tries to perform harvest */
        vm.startPrank(hacker);
        // vm.expectRevert(bytes4(keccak256("OptionsCompounder__OnlyStratAllowed()")));
        // optionsCompounder.harvestOTokens(amount, address(exerciser), NON_ZERO_PROFIT);

        /* Hacker tries to manipulate contract configuration */
        vm.expectRevert("Ownable: caller is not the owner");
        optionsCompounder.setOptionToken(randomOption);

        vm.expectRevert("Ownable: caller is not the owner");
        optionsCompounder.configSwapProps(swapProps);

        vm.expectRevert("Ownable: caller is not the owner");
        optionsCompounder.setOracle(oracle);

        vm.expectRevert("Ownable: caller is not the owner");
        optionsCompounder.setAddressProvider(strategy);
        vm.stopPrank();

        /* Admin tries to set different option token */
        vm.startPrank(owner);
        optionsCompounder.setOptionToken(randomOption);
        vm.stopPrank();
        assertEq(
            address(optionsCompounder.getOptionTokenAddress()),
            randomOption
        );
    }

    function test_flashloanNegativeScenario_highTwapValueAndMultiplier(
        uint256 amount
    ) public {
        /* Test vectors definition */
        amount = bound(
            amount,
            MIN_OATH_FOR_FUZZING,
            1000 * MIN_OATH_FOR_FUZZING
        );

        /* Prepare option tokens - distribute them to the specified strategy
        and approve for spending */
        fixture_prepareOptionToken(
            amount,
            address(optionsCompounder),
            strategy,
            optionsTokenProxy,
            tokenAdmin
        );

        /* Decrease option discount in order to make redemption not profitable */
        /* Notice: Multiplier must be higher than denom because of oracle inaccuracy (initTwap) or just change initTwap */
        vm.startPrank(owner);
        exerciser.setMultiplier(9999);
        vm.stopPrank();
        /* Increase TWAP price to make flashloan not profitable */
        underlyingPaymentMock.setTwapValue(initTwap + ((initTwap * 10) / 100));

        /* Notice: additional protection is in exerciser: Exercise__SlippageTooHigh */
        vm.expectRevert(
            bytes4(
                keccak256("OptionsCompounder__FlashloanNotProfitableEnough()")
            )
        );

        vm.startPrank(strategy);
        /* Already approved in fixture_prepareOptionToken */
        optionsCompounder.harvestOTokens(
            amount,
            address(exerciser),
            NON_ZERO_PROFIT
        );
        vm.stopPrank();
    }

    function test_flashloanNegativeScenario_tooHighMinAmounOfWantExpected(
        uint256 amount,
        uint256 minAmountOfPayment
    ) public {
        /* Test vectors definition */
        amount = bound(
            amount,
            MIN_OATH_FOR_FUZZING,
            underlyingToken.balanceOf(address(exerciser))
        );
        /* Decrease option discount in order to make redemption not profitable */
        /* Notice: Multiplier must be higher than denom because of oracle inaccuracy (initTwap) or just change initTwap */
        vm.startPrank(owner);
        exerciser.setMultiplier(9000);
        vm.stopPrank();
        /* Too high expectation of profit - together with high exerciser multiplier makes flashloan not profitable */
        uint256 paymentAmount = exerciser.getPaymentAmount(amount);

        minAmountOfPayment = bound(
            minAmountOfPayment,
            1e22,
            UINT256_MAX - paymentAmount
        );

        /* Prepare option tokens - distribute them to the specified strategy
        and approve for spending */
        fixture_prepareOptionToken(
            amount,
            address(optionsCompounder),
            address(this),
            optionsTokenProxy,
            tokenAdmin
        );

        /* Notice: additional protection is in exerciser: Exercise__SlippageTooHigh */
        vm.expectRevert(
            bytes4(
                keccak256("OptionsCompounder__FlashloanNotProfitableEnough()")
            )
        );
        /* Already approved in fixture_prepareOptionToken */
        // vm.startPrank(strategy);
        optionsCompounder.harvestOTokens(
            amount,
            address(exerciser),
            minAmountOfPayment
        );
        // vm.stopPrank();
    }

    function test_callExecuteOperationWithoutFlashloanTrigger(
        uint256 amount,
        address executor
    ) public {
        /* Test vectors definition */
        amount = bound(
            amount,
            MIN_OATH_FOR_FUZZING,
            underlyingToken.balanceOf(address(exerciser))
        );

        /* Argument creation */
        address[] memory assets = new address[](1);
        assets[0] = address(paymentToken);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = DiscountExercise(exerciser).getPaymentAmount(amount);
        uint256[] memory premiums = new uint256[](1);
        bytes memory params;

        vm.startPrank(executor);
        /* Assertion */
        vm.expectRevert(
            bytes4(keccak256("OptionsCompounder__FlashloanNotTriggered()"))
        );
        optionsCompounder.executeOperation(
            assets,
            amounts,
            premiums,
            msg.sender,
            params
        );
        vm.stopPrank();
    }

    function test_harvestCallWithWrongExerciseContract(
        uint256 amount,
        address fuzzedExerciser
    ) public {
        /* Test vectors definition */
        amount = bound(
            amount,
            MIN_OATH_FOR_FUZZING,
            underlyingToken.balanceOf(address(exerciser))
        );

        vm.assume(fuzzedExerciser != address(exerciser));

        /* Prepare option tokens - distribute them to the specified strategy
        and approve for spending */
        fixture_prepareOptionToken(
            amount,
            address(optionsCompounder),
            strategy,
            optionsTokenProxy,
            tokenAdmin
        );

        vm.startPrank(strategy);
        /* Assertion */
        vm.expectRevert(
            bytes4(keccak256("OptionsCompounder__NotExerciseContract()"))
        );
        optionsCompounder.harvestOTokens(
            amount,
            fuzzedExerciser,
            NON_ZERO_PROFIT
        );
        vm.stopPrank();
    }
}
