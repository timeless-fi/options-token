// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {ReaperVaultV2} from "vault-v2/ReaperVaultV2.sol";
import {IERC20} from "oz/token/ERC20/IERC20.sol";
import {ReaperSwapper, MinAmountOutData, MinAmountOutKind, IVeloRouter, ISwapRouter, UniV3SwapData} from "vault-v2/ReaperSwapper.sol";
import {OptionsToken} from "../src/OptionsToken.sol";
import {SwapProps, ExchangeType} from "../src/helpers/SwapHelper.sol";
import {ERC1967Proxy} from "oz/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {DiscountExerciseParams, DiscountExercise} from "../src/exercise/DiscountExercise.sol";
import {IOracle} from "../src/interfaces/IOracle.sol";
import {ThenaOracle, IThenaPair} from "../src/oracles/ThenaOracle.sol";
import {IUniswapV3Factory} from "vault-v2/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool, UniswapV3Oracle} from "../src/oracles/UniswapV3Oracle.sol";
import {MockBalancerTwapOracle} from "../test/mocks/MockBalancerTwapOracle.sol";
import {BalancerOracle} from "../src/oracles/BalancerOracle.sol";

error Common__NotYetImplemented();

/* Constants */
uint256 constant NON_ZERO_PROFIT = 1;
uint16 constant PRICE_MULTIPLIER = 5000; // 0.5
uint256 constant INSTANT_EXIT_FEE = 500; // 0.05
uint56 constant ORACLE_SECS = 30 minutes;
uint56 constant ORACLE_AGO = 2 minutes;
uint128 constant ORACLE_MIN_PRICE = 1e7;
uint56 constant ORACLE_LARGEST_SAFETY_WINDOW = 24 hours;
uint256 constant ORACLE_MIN_PRICE_DENOM = 10000;
uint256 constant BPS_DENOM = 10_000;
uint256 constant MAX_SUPPLY = 1e27; // the max supply of the options token & the underlying token

uint256 constant AMOUNT = 2e18; // 2 ETH
address constant REWARDER = 0x6A0406B8103Ec68EE9A713A073C7bD587c5e04aD;
uint256 constant MIN_OATH_FOR_FUZZING = 1e19;

/* OP */
address constant OP_POOL_ADDRESSES_PROVIDER_V2 = 0xdDE5dC81e40799750B92079723Da2acAF9e1C6D6; // Granary (aavev2)
// AAVEv3 - 0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb;
address constant OP_WETH = 0x4200000000000000000000000000000000000006;
address constant OP_OATHV1 = 0x39FdE572a18448F8139b7788099F0a0740f51205;
address constant OP_OATHV2 = 0x00e1724885473B63bCE08a9f0a52F35b0979e35A;
address constant OP_CUSDC = 0xEC8FEa79026FfEd168cCf5C627c7f486D77b765F;
address constant OP_GUSDC = 0x7A0FDDBA78FF45D353B1630B77f4D175A00df0c0;
address constant OP_GOP = 0x30091e843deb234EBb45c7E1Da4bBC4C33B3f0B4;
address constant OP_SOOP = 0x8cD6b19A07d754bF36AdEEE79EDF4F2134a8F571;
address constant OP_USDC = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
address constant OP_OP = 0x4200000000000000000000000000000000000042;
/* Balancer */
address constant OP_DATA_PROVIDER = 0x9546F673eF71Ff666ae66d01Fd6E7C6Dae5a9995;
bytes32 constant OP_OATHV1_ETH_BPT = 0xd20f6f1d8a675cdca155cb07b5dc9042c467153f0002000000000000000000bc; // OATHv1/ETH BPT
bytes32 constant OP_OATHV2_ETH_BPT = 0xd13d81af624956327a24d0275cbe54b0ee0e9070000200000000000000000109; // OATHv2/ETH BPT
bytes32 constant OP_BTC_WETH_USDC_BPT = 0x5028497af0c9a54ea8c6d42a054c0341b9fc6168000100000000000000000004;
bytes32 constant OP_WETH_OP_USDC_BPT = 0x39965c9dab5448482cf7e002f583c812ceb53046000100000000000000000003;
address constant OP_BEETX_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
/* Uniswap */
address constant OP_UNIV3_ROUTERV = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
address constant OP_UNIV3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
/* Velodrome */
address constant OP_VELO_OATHV2_ETH_PAIR = 0xc3439bC1A747e545887192d6b7F8BE47f608473F;
address constant OP_VELO_ROUTER = 0xa062aE8A9c5e11aaA026fc2670B0D65cCc8B2858;
address constant OP_VELO_FACTORY = 0xF1046053aa5682b4F9a81b5481394DA16BE5FF5a;

/* BSC */
address constant BSC_LENDING_POOL = 0xad441B19a9948c3a3f38C0AB6CCbd853036851d2;
address constant BSC_ADDRESS_PROVIDER = 0xcD2f1565e6d2A83A167FDa6abFc10537d4e984f0;
address constant BSC_DATA_PROVIDER = 0xFa0AC9b741F0868B2a8C4a6001811a5153019818;
address constant BSC_HBR = 0x42c95788F791a2be3584446854c8d9BB01BE88A9;
address constant BSC_USDT = 0x55d398326f99059fF775485246999027B3197955;
address constant BSC_BTCB = 0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c;
address constant BSC_WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
address constant BSC_GUSDT = 0x686C55C8344E902CD8143Cf4BDF2c5089Be273c5;
address constant BSC_THENA_ROUTER = 0xd4ae6eCA985340Dd434D38F470aCCce4DC78D109;
address constant BSC_THENA_FACTORY = 0x2c788FE40A417612cb654b14a944cd549B5BF130;
address constant BSC_UNIV3_ROUTERV2 = 0xB971eF87ede563556b2ED4b1C0b0019111Dd85d2;
address constant BSC_UNIV3_FACTORY = 0xdB1d10011AD0Ff90774D0C6Bb92e5C5c8b4461F7;
address constant BSC_PANCAKE_ROUTER = 0x1b81D678ffb9C0263b24A97847620C99d213eB14;
address constant BSC_PANCAKE_FACTORY = 0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865;
address constant BSC_REWARDER = 0x071c626C75248E4F672bAb8c21c089166F49B615;

/* ARB */
address constant ARB_USDCE = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
address constant ARB_USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
address constant ARB_RAM = 0xAAA6C1E32C55A7Bfa8066A6FAE9b42650F262418;
address constant ARB_WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
/* Ramses */
address constant ARB_RAM_ROUTER = 0xAAA87963EFeB6f7E0a2711F397663105Acb1805e;
address constant ARB_RAM_ROUTERV2 = 0xAA23611badAFB62D37E7295A682D21960ac85A90; //univ3
address constant ARB_RAM_FACTORYV2 = 0xAA2cd7477c451E703f3B9Ba5663334914763edF8;

/* MODE */
address constant MODE_MODE = 0xDfc7C877a950e49D2610114102175A06C2e3167a;
address constant MODE_USDC = 0xd988097fb8612cc24eeC14542bC03424c656005f;
address constant MODE_WETH = 0x4200000000000000000000000000000000000006;
/* Velodrome */
address constant MODE_VELO_USDC_MODE_PAIR = 0x283bA4E204DFcB6381BCBf2cb5d0e765A2B57bC2; // DECIMALS ISSUE
address constant MODE_VELO_WETH_MODE_PAIR = 0x0fba984c97539B3fb49ACDA6973288D0EFA903DB;
address constant MODE_VELO_ROUTER = 0x3a63171DD9BebF4D07BC782FECC7eb0b890C2A45;
address constant MODE_VELO_FACTORY = 0x31832f2a97Fd20664D76Cc421207669b55CE4BC0;
address constant MODE_ADDRESS_PROVIDER = 0xEDc83309549e36f3c7FD8c2C5C54B4c8e5FA00FC;

contract Common is Test {
    IERC20 nativeToken;
    IERC20 paymentToken;
    IERC20 underlyingToken;
    IERC20 wantToken;
    IVeloRouter veloRouter;
    ISwapRouter swapRouter;
    IUniswapV3Factory univ3Factory;
    ReaperSwapper reaperSwapper;
    MockBalancerTwapOracle underlyingPaymentMock;

    address[] treasuries;
    uint256[] feeBPS;
    bytes32 paymentUnderlyingBpt;
    bytes32 paymentWantBpt;

    address veloFactory;
    address pool;
    address addressProvider;
    address dataProvider;
    address rewarder;
    address balancerVault;
    address owner;
    address gWantAddress;
    address tokenAdmin;
    address strategist = address(4);
    address vault;
    address management1;
    address management2;
    address management3;
    address keeper;

    uint256 targetLtv = 0.77 ether;
    uint256 maxLtv = 0.771 ether;

    OptionsToken optionsToken;
    ERC1967Proxy tmpProxy;
    OptionsToken optionsTokenProxy;
    DiscountExercise exerciser;

    uint256 maxUnderlyingAmount;

    function fixture_setupAccountsAndFees(uint256 fee1, uint256 fee2) public {
        /* Setup accounts */
        owner = makeAddr("owner");
        tokenAdmin = makeAddr("tokenAdmin");
        treasuries = new address[](2);
        treasuries[0] = makeAddr("treasury1");
        treasuries[1] = makeAddr("treasury2");
        vault = makeAddr("vault");
        management1 = makeAddr("management1");
        management2 = makeAddr("management2");
        management3 = makeAddr("management3");
        keeper = makeAddr("keeper");

        feeBPS = new uint256[](2);
        feeBPS[0] = fee1;
        feeBPS[1] = fee2;
    }

    /* Functions */
    function fixture_prepareOptionToken(uint256 _amount, address _compounder, address _strategy, OptionsToken _optionsToken, address _tokenAdmin)
        public
    {
        /* Mint options tokens and transfer them to the strategy (rewards simulation) */
        vm.prank(_tokenAdmin);
        _optionsToken.mint(_strategy, _amount);
        vm.prank(_strategy);
        _optionsToken.approve(_compounder, _amount);
    }

    function fixture_updateSwapperPaths(ExchangeType exchangeType) public {
        address[2] memory paths = [address(underlyingToken), address(paymentToken)];

        if (exchangeType == ExchangeType.Bal) {
            /* Configure balancer like dexes */
            reaperSwapper.updateBalSwapPoolID(paths[0], paths[1], balancerVault, paymentUnderlyingBpt);
            reaperSwapper.updateBalSwapPoolID(paths[1], paths[0], balancerVault, paymentUnderlyingBpt);
        } else if (exchangeType == ExchangeType.VeloSolid) {
            /* Configure thena ram like dexes */
            IVeloRouter.Route[] memory veloPath = new IVeloRouter.Route[](1);
            veloPath[0] = IVeloRouter.Route(paths[0], paths[1], false);
            reaperSwapper.updateVeloSwapPath(paths[0], paths[1], address(veloRouter), veloPath);
            veloPath[0] = IVeloRouter.Route(paths[1], paths[0], false);
            reaperSwapper.updateVeloSwapPath(paths[1], paths[0], address(veloRouter), veloPath);
        } else if (exchangeType == ExchangeType.UniV3) {
            /* Configure univ3 like dexes */
            uint24[] memory univ3Fees = new uint24[](1);
            univ3Fees[0] = 500;
            address[] memory univ3Path = new address[](2);

            univ3Path[0] = paths[0];
            univ3Path[1] = paths[1];
            UniV3SwapData memory swapPathAndFees = UniV3SwapData(univ3Path, univ3Fees);
            reaperSwapper.updateUniV3SwapPath(paths[0], paths[1], address(swapRouter), swapPathAndFees);
        } else {
            revert Common__NotYetImplemented();
        }
    }

    function fixture_getMockedOracle(ExchangeType exchangeType) public returns (IOracle) {
        IOracle oracle;
        address[] memory _tokens = new address[](2);
        _tokens[0] = address(paymentToken);
        _tokens[1] = address(underlyingToken);
        if (exchangeType == ExchangeType.Bal) {
            BalancerOracle underlyingPaymentOracle;
            underlyingPaymentMock = new MockBalancerTwapOracle(_tokens);
            underlyingPaymentOracle =
                new BalancerOracle(underlyingPaymentMock, address(underlyingToken), owner, ORACLE_SECS, ORACLE_AGO, ORACLE_MIN_PRICE);
            oracle = underlyingPaymentOracle;
        } else if (exchangeType == ExchangeType.VeloSolid) {
            IVeloRouter router = IVeloRouter(payable(address(veloRouter)));
            ThenaOracle underlyingPaymentOracle;
            address pair = router.poolFor(address(underlyingToken), address(paymentToken), false);
            underlyingPaymentOracle = new ThenaOracle(IThenaPair(pair), address(underlyingToken), owner, ORACLE_SECS, ORACLE_MIN_PRICE);
            oracle = IOracle(address(underlyingPaymentOracle));
        } else if (exchangeType == ExchangeType.UniV3) {
            IUniswapV3Pool univ3Pool = IUniswapV3Pool(univ3Factory.getPool(address(underlyingToken), address(paymentToken), 500));
            UniswapV3Oracle univ3Oracle =
                new UniswapV3Oracle(univ3Pool, address(paymentToken), owner, uint32(ORACLE_SECS), uint32(ORACLE_AGO), ORACLE_MIN_PRICE);
            oracle = IOracle(address(univ3Oracle));
        } else {
            revert Common__NotYetImplemented();
        }
        return oracle;
    }

    function fixture_getSwapProps(ExchangeType exchangeType, uint256 slippage) public view returns (SwapProps memory) {
        SwapProps memory swapProps;

        if (exchangeType == ExchangeType.Bal) {
            swapProps = SwapProps(address(reaperSwapper), address(swapRouter), ExchangeType.Bal, slippage);
        } else if (exchangeType == ExchangeType.VeloSolid) {
            swapProps = SwapProps(address(reaperSwapper), address(veloRouter), ExchangeType.VeloSolid, slippage);
        } else if (exchangeType == ExchangeType.UniV3) {
            swapProps = SwapProps(address(reaperSwapper), address(swapRouter), ExchangeType.UniV3, slippage);
        } else {
            revert Common__NotYetImplemented();
        }
        return swapProps;
    }
}
