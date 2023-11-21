// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {ThenaOracle} from "../src/oracles/ThenaOracle.sol";
import {IThenaPair} from "../src/interfaces/IThenaPair.sol";
import {IThenaRouter} from "./interfaces/IThenaRouter.sol";
import {TickMath} from "v3-core/libraries/TickMath.sol";
import {FullMath} from "v3-core/libraries/FullMath.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

struct Params {
    IThenaPair pair;
    address token;
    address owner;
    uint16 multiplier;
    uint32 secs;
    uint128 minPrice;
}

contract UniswapOracleTest is Test {
    using stdStorage for StdStorage;
    using FixedPointMathLib for uint256;

    string BSC_RPC_URL = vm.envString("BSC_RPC_URL");
    uint32 FORK_BLOCK = 33672842;
    
    address THENA_POOL_ADDRESS = 0x63Db6ba9E512186C2FAaDaCEF342FB4A40dc577c;
    address THENA_ADDRESS = 0xF4C8E32EaDEC4BFe97E0F595AdD0f4450a863a11;
    address BNB_ADDRESS = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address THENA_ROUTER = 0xd4ae6eCA985340Dd434D38F470aCCce4DC78D109;

    uint256 bscFork;

    Params _default;

    function setUp() public {
        _default = Params(IThenaPair(THENA_POOL_ADDRESS), THENA_ADDRESS, address(this), 10000, 30 minutes, 1000);
        bscFork = vm.createSelectFork(BSC_RPC_URL, FORK_BLOCK);
    }

    function test_priceWithinAcceptableRange() public {

        ThenaOracle oracle = new ThenaOracle(
            _default.pair,
            _default.token,
            _default.owner,
            _default.multiplier,
            _default.secs,
            _default.minPrice
        );

        uint oraclePrice = oracle.getPrice();

        uint256 spotPrice = getSpotPrice(_default.pair, _default.token);
        assertApproxEqRel(oraclePrice, spotPrice, 0.01 ether, "Price delta too big"); // 1%
    }

    function test_priceManipulation() public {
        ThenaOracle oracle = new ThenaOracle(
            _default.pair,
            _default.token,
            _default.owner,
            _default.multiplier,
            _default.secs,
            _default.minPrice
        );

        address manipulator1 = makeAddr("manipulator");
        deal(THENA_ADDRESS, manipulator1, 1000000 ether);

        // register initial oracle price
        uint256 price_1 = oracle.getPrice();

        // perform a large swap
        vm.startPrank(manipulator1);
        IERC20(THENA_ADDRESS).approve(THENA_ROUTER, 1000000 ether);

        (uint256 reserve0, uint256 reserve1,) = _default.pair.getReserves();
        (uint256[] memory amountOut) = IThenaRouter(THENA_ROUTER).swapExactTokensForTokensSimple(
            (THENA_ADDRESS == _default.pair.token0() ? reserve0 : reserve1) / 10,
            0,
            THENA_ADDRESS,
            BNB_ADDRESS,
            false,
            manipulator1,
            type(uint32).max
        );
        vm.stopPrank();

        // wait 60 seconds
        skip(1 minutes);
        
        // perform additional, smaller swap
        address manipulator2 = makeAddr("manipulator");
        deal(BNB_ADDRESS, manipulator2, amountOut[0] / 1000);
        vm.startPrank(manipulator2);
        IERC20(BNB_ADDRESS).approve(THENA_ROUTER, 1000000 ether);

        IThenaRouter(THENA_ROUTER).swapExactTokensForTokensSimple(
            amountOut[0] / 1000,
            0,
            BNB_ADDRESS,
            THENA_ADDRESS,
            false,
            manipulator2,
            type(uint32).max
        );
        vm.stopPrank();
        
        assertApproxEqRel(price_1, oracle.getPrice(), 0.01 ether, "price variance too large");
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

}
