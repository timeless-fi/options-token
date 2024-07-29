// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {ThenaOracle} from "../src/oracles/ThenaOracle.sol";
import {IThenaPair} from "../src/interfaces/IThenaPair.sol";
import {IThenaRouter} from "./interfaces/IThenaRouter.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

struct Params {
    IThenaPair pair;
    address token;
    address owner;
    uint32 secs;
    uint128 minPrice;
}

contract ThenaOracleTest is Test {
    using stdStorage for StdStorage;
    using FixedPointMathLib for uint256;

    string BSC_RPC_URL = vm.envString("BSC_RPC_URL");
    uint32 FORK_BLOCK = 33672842;

    address POOL_ADDRESS = 0x56EDFf25385B1DaE39d816d006d14CeCf96026aF;
    address TOKEN_ADDRESS = 0x4d2d32d8652058Bf98c772953E1Df5c5c85D9F45;
    address PAYMENT_TOKEN_ADDRESS = 0x55d398326f99059fF775485246999027B3197955;
    address THENA_ROUTER = 0xd4ae6eCA985340Dd434D38F470aCCce4DC78D109;

    uint256 MULTIPLIER_DENOM = 10000;

    uint256 bscFork;

    Params _default;

    function setUp() public {
        _default = Params(IThenaPair(POOL_ADDRESS), TOKEN_ADDRESS, address(this), 30 minutes, 1000);
        bscFork = vm.createSelectFork(BSC_RPC_URL, FORK_BLOCK);
    }

    function test_priceWithinAcceptableRange() public {
        ThenaOracle oracle = new ThenaOracle(
            _default.pair,
            _default.token,
            _default.owner,
            _default.secs,
            _default.minPrice
        );

        uint256 oraclePrice = oracle.getPrice();

        uint256 spotPrice = getSpotPrice(_default.pair, _default.token);
        assertApproxEqRel(oraclePrice, spotPrice, 0.01 ether, "Price delta too large"); // 1%
    }

    function test_priceToken1() public {
        ThenaOracle oracleToken0 = new ThenaOracle(
            _default.pair,
            IThenaPair(_default.pair).token0(),
            _default.owner,
            _default.secs,
            _default.minPrice
        );

        ThenaOracle oracleToken1 = new ThenaOracle(
            _default.pair,
            IThenaPair(_default.pair).token1(),
            _default.owner,
            _default.secs,
            _default.minPrice
        );

        uint256 priceToken0 = oracleToken0.getPrice();
        uint256 priceToken1 = oracleToken1.getPrice();

        assertApproxEqAbs(priceToken1, uint256(1e18).divWadDown(priceToken0), 1, "incorrect price"); // 1%
    }

    function test_revertMinPrice() public {
        ThenaOracle oracle = new ThenaOracle(
            _default.pair,
            _default.token,
            _default.owner,
            _default.secs,
            _default.minPrice
        );

        // clean twap for test
        skip(1 hours);
        _default.pair.sync();
        skip(1 hours);
        _default.pair.sync();
        skip(1 hours);

        // register initial oracle price
        uint256 price = oracle.getPrice();

        // drag price below min
        uint256 amountIn = 10000000;
        deal(TOKEN_ADDRESS, address(this), amountIn);
        IERC20(TOKEN_ADDRESS).approve(THENA_ROUTER, amountIn);
        IThenaRouter(THENA_ROUTER).swapExactTokensForTokensSimple(
            amountIn, 0, TOKEN_ADDRESS, PAYMENT_TOKEN_ADDRESS, false, address(this), type(uint32).max
        );

        ThenaOracle oracleMinPrice = new ThenaOracle(
            _default.pair,
            _default.token,
            _default.owner,
            _default.secs,
            uint128(price)
        );

        skip(_default.secs);

        vm.expectRevert(ThenaOracle.ThenaOracle__BelowMinPrice.selector);
        oracleMinPrice.getPrice();
    }

    function test_singleBlockManipulation() public {
        ThenaOracle oracle = new ThenaOracle(
            _default.pair,
            _default.token,
            _default.owner,
            _default.secs,
            _default.minPrice
        );

        address manipulator = makeAddr("manipulator");
        deal(TOKEN_ADDRESS, manipulator, 1000000 ether);

        // register initial oracle price
        uint256 price_1 = oracle.getPrice();

        // perform a large swap
        vm.startPrank(manipulator);
        IERC20(TOKEN_ADDRESS).approve(THENA_ROUTER, 1000000 ether);

        (uint256 reserve0, uint256 reserve1,) = _default.pair.getReserves();
        IThenaRouter(THENA_ROUTER).swapExactTokensForTokensSimple(
            (TOKEN_ADDRESS == _default.pair.token0() ? reserve0 : reserve1) / 10,
            0,
            TOKEN_ADDRESS,
            PAYMENT_TOKEN_ADDRESS,
            false,
            manipulator,
            type(uint32).max
        );
        vm.stopPrank();

        // price should not have changed
        assertEq(oracle.getPrice(), price_1, "single block price variation");
    }

    function test_priceManipulation(uint256 skipTime) public {
        skipTime = bound(skipTime, 1, _default.secs);
        ThenaOracle oracle = new ThenaOracle(
            _default.pair,
            _default.token,
            _default.owner,
            _default.secs,
            _default.minPrice
        );

        // clean twap for test
        skip(1 hours);
        _default.pair.sync();
        skip(1 hours);
        _default.pair.sync();
        skip(1 hours);

        // register initial oracle price
        uint256 price_1 = oracle.getPrice();

        // perform a large swap
        address manipulator = makeAddr("manipulator");
        deal(TOKEN_ADDRESS, manipulator, 2 ** 128);
        vm.startPrank(manipulator);
        (uint256 reserve0, uint256 reserve1,) = _default.pair.getReserves();
        uint256 amountIn = (TOKEN_ADDRESS == _default.pair.token0() ? reserve0 : reserve1) / 4;
        IERC20(TOKEN_ADDRESS).approve(THENA_ROUTER, amountIn);
        IThenaRouter(THENA_ROUTER).swapExactTokensForTokensSimple(
            amountIn, 0, TOKEN_ADDRESS, PAYMENT_TOKEN_ADDRESS, false, manipulator, type(uint32).max
        );
        vm.stopPrank();

        // wait
        skip(skipTime);

        uint256 expectedMinPrice = (price_1 * (_default.secs - skipTime) + getSpotPrice(_default.pair, _default.token) * skipTime) / _default.secs;

        assertGeDecimal(oracle.getPrice(), expectedMinPrice, 18, "price variation too large");
    }

    function getSpotPrice(IThenaPair pair, address token) internal view returns (uint256 price) {
        bool isToken0 = token == pair.token0();
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        if (isToken0) {
            price = uint256(reserve1).divWadDown(reserve0);
        } else {
            price = uint256(reserve0).divWadDown(reserve1);
        }
    }

    function max(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x > y ? x : y;
    }
}
