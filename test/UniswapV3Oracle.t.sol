// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {UniswapV3Oracle} from "../src/oracles/UniswapV3Oracle.sol";
import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {TickMath} from "v3-core/libraries/TickMath.sol";
import {FullMath} from "v3-core/libraries/FullMath.sol";
import {ISwapRouter} from "./interfaces/ISwapRouter.sol";
import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {MockUniswapPool} from "./mocks/MockUniswapPool.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

struct Params {
    IUniswapV3Pool pool;
    address token;
    address owner;
    uint32 secs;
    uint32 ago;
    uint128 minPrice;
}

contract UniswapOracleTest is Test {
    using stdStorage for StdStorage;

    // mock config
    Params _mock;
    MockUniswapPool mockV3Pool;
    // observation on 2023-09-20 11:26 UTC-3, UNIWETH Ethereum Pool
    int56[2] sampleCumulatives = [int56(-4072715107990), int56(-4072608557758)];
    // expected price in terms of token0
    uint256 expectedPriceToken0 = 372078200928347021722;

    string OPTIMISM_RPC_URL = vm.envString("OPTIMISM_RPC_URL");
    uint32 FORK_BLOCK = 112198905;

    address SWAP_ROUTER_ADDRESS = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address WETH_OP_POOL_ADDRESS = 0x68F5C0A2DE713a54991E01858Fd27a3832401849;
    address OP_ADDRESS = 0x4200000000000000000000000000000000000042;
    address WETH_ADDRESS = 0x4200000000000000000000000000000000000006;
    uint24 POOL_FEE = 3000;

    uint256 opFork;

    ISwapRouter swapRouter;
    Params _default;

    function setUp() public {
        opFork = vm.createSelectFork(OPTIMISM_RPC_URL, FORK_BLOCK);
        mockV3Pool = new MockUniswapPool();
        mockV3Pool.setCumulatives(sampleCumulatives);
        mockV3Pool.setToken0(OP_ADDRESS);
        mockV3Pool.setToken1(WETH_ADDRESS);

        _default = Params(IUniswapV3Pool(WETH_OP_POOL_ADDRESS), OP_ADDRESS, address(this), 30 minutes, 0, 1000);
        swapRouter = ISwapRouter(SWAP_ROUTER_ADDRESS);
    }

    /// ----------------------------------------------------------------------
    /// Mock tests
    /// ----------------------------------------------------------------------

    function test_PriceTokens() public {
        UniswapV3Oracle oracle0 = new UniswapV3Oracle(mockV3Pool, OP_ADDRESS, _default.owner, _default.secs, _default.ago, _default.minPrice);
        UniswapV3Oracle oracle1 = new UniswapV3Oracle(mockV3Pool, WETH_ADDRESS, _default.owner, _default.secs, _default.ago, _default.minPrice);

        uint256 price0 = oracle0.getPrice();
        uint256 price1 = oracle1.getPrice();
        assertEq(price0, expectedPriceToken0);
        uint256 expectedPriceToken1 = FixedPointMathLib.divWadDown(1e18, price0);
        assertEq(price1, expectedPriceToken1); //precision
    }

    /// ----------------------------------------------------------------------
    /// Fork tests
    /// ----------------------------------------------------------------------

    function test_priceWithinAcceptableRange() public {
        UniswapV3Oracle oracle = new UniswapV3Oracle(_default.pool, _default.token, _default.owner, _default.secs, _default.ago, _default.minPrice);

        uint256 oraclePrice = oracle.getPrice();

        (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(WETH_OP_POOL_ADDRESS).slot0();
        uint256 spotPrice = computePriceFromX96(sqrtRatioX96);
        assertApproxEqRel(oraclePrice, spotPrice, 0.01 ether, "Price delta too big"); // 1%
    }

    function test_revertMinPrice() public {
        UniswapV3Oracle oracle = new UniswapV3Oracle(_default.pool, _default.token, _default.owner, _default.secs, _default.ago, _default.minPrice);

        skip(_default.secs);

        uint256 price = oracle.getPrice();

        uint256 amountIn = 100000 ether;
        deal(OP_ADDRESS, address(this), amountIn);
        ISwapRouter.ExactInputSingleParams memory paramsIn = ISwapRouter.ExactInputSingleParams({
            tokenIn: OP_ADDRESS,
            tokenOut: WETH_ADDRESS,
            fee: POOL_FEE,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        IERC20(OP_ADDRESS).approve(address(swapRouter), amountIn);
        swapRouter.exactInputSingle(paramsIn);

        // deploy a new oracle with a minPrice that is too high
        UniswapV3Oracle oracleMinPrice =
            new UniswapV3Oracle(_default.pool, _default.token, _default.owner, _default.secs, _default.ago, uint128(price));

        skip(_default.secs);

        vm.expectRevert(UniswapV3Oracle.UniswapOracle__BelowMinPrice.selector);
        oracleMinPrice.getPrice();
    }

    function test_singleBlockManipulation() public {
        UniswapV3Oracle oracle = new UniswapV3Oracle(_default.pool, _default.token, _default.owner, _default.secs, _default.ago, _default.minPrice);

        address manipulator = makeAddr("manipulator");
        deal(OP_ADDRESS, manipulator, 1000000 ether);

        // register initial oracle price
        uint256 price_1 = oracle.getPrice();

        // perform a large swap
        vm.startPrank(manipulator);
        uint256 reserve = IERC20(OP_ADDRESS).balanceOf(WETH_OP_POOL_ADDRESS);
        uint256 amountIn = reserve / 4;
        ISwapRouter.ExactInputSingleParams memory paramsIn = ISwapRouter.ExactInputSingleParams({
            tokenIn: OP_ADDRESS,
            tokenOut: WETH_ADDRESS,
            fee: POOL_FEE,
            recipient: manipulator,
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        IERC20(OP_ADDRESS).approve(address(swapRouter), amountIn);
        swapRouter.exactInputSingle(paramsIn);
        vm.stopPrank();

        // price should not have changed
        assertEqDecimal(price_1, oracle.getPrice(), 18);
    }

    function test_priceManipulation(uint256 skipTime) public {
        skipTime = bound(skipTime, 1, _default.secs);

        UniswapV3Oracle oracle = new UniswapV3Oracle(_default.pool, _default.token, _default.owner, _default.secs, _default.ago, _default.minPrice);

        address manipulator = makeAddr("manipulator");
        deal(OP_ADDRESS, manipulator, 1000000 ether);

        // register initial oracle price
        uint256 price_1 = oracle.getPrice();

        // perform a large swap
        vm.startPrank(manipulator);
        uint256 reserve = IERC20(OP_ADDRESS).balanceOf(WETH_OP_POOL_ADDRESS);
        uint256 amountIn = reserve / 4;
        ISwapRouter.ExactInputSingleParams memory paramsIn = ISwapRouter.ExactInputSingleParams({
            tokenIn: OP_ADDRESS,
            tokenOut: WETH_ADDRESS,
            fee: POOL_FEE,
            recipient: manipulator,
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        IERC20(OP_ADDRESS).approve(address(swapRouter), amountIn);
        swapRouter.exactInputSingle(paramsIn);
        vm.stopPrank();

        // wait
        skip(skipTime);

        (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(WETH_OP_POOL_ADDRESS).slot0();
        uint256 spotPrice = computePriceFromX96(sqrtRatioX96);
        uint256 expectedPrice = (price_1 * (_default.secs - skipTime) + spotPrice * skipTime) / _default.secs;

        assertApproxEqRel(oracle.getPrice(), expectedPrice, 0.001 ether, "price variance too large");
    }

    function computePriceFromX96(uint160 sqrtRatioX96) internal view returns (uint256 price) {
        bool isToken0 = OP_ADDRESS == IUniswapV3Pool(WETH_OP_POOL_ADDRESS).token0();
        uint256 decimals = 1e18;

        if (sqrtRatioX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
            price = isToken0 ? FullMath.mulDiv(ratioX192, decimals, 1 << 192) : FullMath.mulDiv(1 << 192, decimals, ratioX192);
        } else {
            uint256 ratioX128 = FullMath.mulDiv(sqrtRatioX96, sqrtRatioX96, 1 << 64);
            price = isToken0 ? FullMath.mulDiv(ratioX128, decimals, 1 << 128) : FullMath.mulDiv(1 << 128, decimals, ratioX128);
        }
    }
}
