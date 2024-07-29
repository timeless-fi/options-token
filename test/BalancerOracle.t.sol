// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {BalancerOracle} from "../src/oracles/BalancerOracle.sol";
import {IBalancerTwapOracle} from "../src/interfaces/IBalancerTwapOracle.sol";
import {IVault, IAsset} from "../src/interfaces/IBalancerVault.sol";
import {IBalancer2TokensPool} from "../src/interfaces/IBalancer2TokensPool.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

struct Params {
    IBalancerTwapOracle pair;
    address token;
    address owner;
    uint32 secs;
    uint32 ago;
    uint128 minPrice;
}

contract BalancerOracleTest is Test {
    using stdStorage for StdStorage;
    using FixedPointMathLib for uint256;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    uint32 FORK_BLOCK = 18764758;

    address TOKEN_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address PAYMENT_ADDRESS = 0xfd0205066521550D7d7AB19DA8F72bb004b4C341;
    address POOL_ADDRESS = 0x9232a548DD9E81BaC65500b5e0d918F8Ba93675C;

    uint256 MULTIPLIER_DENOM = 10000;

    uint256 opFork;

    Params _default;

    function setUp() public {
        _default = Params(IBalancerTwapOracle(POOL_ADDRESS), TOKEN_ADDRESS, address(this), 30 minutes, 0, 1000);
        opFork = vm.createSelectFork(MAINNET_RPC_URL, FORK_BLOCK);
    }

    function test_priceWithinAcceptableRange() public {
        BalancerOracle oracle = new BalancerOracle(
            _default.pair,
            _default.token,
            _default.owner,
            _default.secs,
            _default.ago,
            _default.minPrice
        );

        uint256 oraclePrice = oracle.getPrice();

        uint256 spotPrice = getSpotPrice(address(_default.pair), _default.token);
        assertApproxEqRel(oraclePrice, spotPrice, 0.01 ether, "Price delta too big"); // 1%
    }

    function test_priceToken1() public {
        IVault vault = _default.pair.getVault();
        (address[] memory poolTokens,,) = vault.getPoolTokens(_default.pair.getPoolId());

        BalancerOracle oracleToken0 = new BalancerOracle(
            _default.pair,
            poolTokens[0],
            _default.owner,
            _default.secs,
            _default.ago,
            _default.minPrice
        );

        BalancerOracle oracleToken1 = new BalancerOracle(
            _default.pair,
            poolTokens[1],
            _default.owner,
            _default.secs,
            _default.ago,
            _default.minPrice
        );

        uint256 priceToken0 = oracleToken0.getPrice();
        uint256 priceToken1 = oracleToken1.getPrice();

        assertEq(priceToken1, uint256(1e18).divWadUp(priceToken0), "incorrect price"); // 1%
    }

    function test_singleBlockManipulation() public {
        IVault vault = _default.pair.getVault();
        BalancerOracle oracle = new BalancerOracle(
            _default.pair,
            _default.token,
            _default.owner,
            _default.secs,
            _default.ago,
            _default.minPrice
        );

        address manipulator1 = makeAddr("manipulator");
        deal(TOKEN_ADDRESS, manipulator1, 1000000 ether);

        vm.startPrank(manipulator1);
        IERC20(TOKEN_ADDRESS).approve(address(vault), 1000000 ether);

        (address[] memory tokens, uint256[] memory reserves,) = vault.getPoolTokens(_default.pair.getPoolId());

        // swap 1 token to update oracle to latest block
        swap(address(_default.pair), tokens[0], tokens[1], 1, manipulator1);

        // register initial oracle price
        uint256 price_1 = oracle.getPrice();

        swap(address(_default.pair), tokens[0], tokens[1], reserves[0] / 10, manipulator1);

        vm.stopPrank();

        // check price variation
        assertEq(oracle.getPrice(), price_1, "single block price variation");
    }

    function test_priceManipulation(uint256 skipTime) public {
        skipTime = bound(skipTime, 1, _default.secs);
        IVault vault = _default.pair.getVault();
        BalancerOracle oracle = new BalancerOracle(
            _default.pair,
            _default.token,
            _default.owner,
            _default.secs,
            _default.ago,
            _default.minPrice
        );

        address manipulator1 = makeAddr("manipulator");
        deal(TOKEN_ADDRESS, manipulator1, 1000000 ether);

        vm.startPrank(manipulator1);

        // swap 1 token to update oracle to latest block
        IERC20(TOKEN_ADDRESS).approve(address(vault), 1000000 ether);
        swap(address(_default.pair), TOKEN_ADDRESS, PAYMENT_ADDRESS, 1, manipulator1);

        // register initial oracle price
        uint256 price_1 = oracle.getPrice();

        // perform a large swap (25% of reserves)
        (address[] memory tokens, uint256[] memory reserves,) = vault.getPoolTokens(_default.pair.getPoolId());
        swap(address(_default.pair), tokens[0], tokens[1], reserves[0] / 4, manipulator1);

        vm.stopPrank();

        // wait
        skip(skipTime);
        // update block
        vm.roll(block.number + 1);

        // oracle price is only updated on swaps
        assertEq(price_1, oracle.getPrice(), "price updated");

        // perform additional, smaller swap
        address manipulator2 = makeAddr("manipulator2");
        deal(PAYMENT_ADDRESS, manipulator2, 1);
        vm.startPrank(manipulator2);
        IERC20(PAYMENT_ADDRESS).approve(address(vault), 1);
        swap(address(_default.pair), tokens[1], tokens[0], 1, manipulator2);
        vm.stopPrank();

        // weighted average of the first recorded oracle price and the current spot price
        // weighted by the time since the last update
        uint256 spotAverage =
            ((price_1 * (_default.secs - skipTime)) + (getSpotPrice(address(_default.pair), _default.token) * skipTime)) / _default.secs;

        assertApproxEqRel(spotAverage, oracle.getPrice(), 0.01 ether, "price variance too large");
    }

    function getSpotPrice(address pool, address token) internal view returns (uint256 price) {
        IVault vault = IBalancerTwapOracle(pool).getVault();
        bytes32 poolId = IBalancerTwapOracle(pool).getPoolId();
        (address[] memory poolTokens,,) = vault.getPoolTokens(poolId);

        bool isToken0 = token == poolTokens[0];
        (, uint256[] memory balances,) = vault.getPoolTokens(poolId);
        uint256[] memory weights = IBalancer2TokensPool(pool).getNormalizedWeights();

        price = isToken0
            ? (balances[1] * weights[0]).divWadDown(balances[0] * weights[1])
            : (balances[0] * weights[1]).divWadDown(balances[1] * weights[0]);
    }

    function swap(address pool, address tokenIn, address tokenOut, uint256 amountIn, address sender) internal returns (uint256 amountOut) {
        bytes32 poolId = IBalancerTwapOracle(pool).getPoolId();
        IVault.SingleSwap memory singleSwap = IVault.SingleSwap(poolId, IVault.SwapKind.GIVEN_IN, IAsset(tokenIn), IAsset(tokenOut), amountIn, "");

        IVault.FundManagement memory funds = IVault.FundManagement(sender, false, payable(sender), false);

        return IVault(IBalancer2TokensPool(pool).getVault()).swap(singleSwap, funds, 0, type(uint256).max);
    }
}
