// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {IERC20Mintable} from "../src/interfaces/IERC20Mintable.sol";

import {OptionsToken} from "../src/OptionsToken.sol";
import {BalancerOracle} from "../src/oracles/BalancerOracle.sol";
import {IBalancerPriceOracle} from "../src/interfaces/IBalancerPriceOracle.sol";

contract DeployScript is Script {
    function run() public returns (OptionsToken optionsToken, BalancerOracle oracle) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        vm.startBroadcast(deployerPrivateKey);

        {
            IBalancerPriceOracle balancerPriceOracle = IBalancerPriceOracle(vm.envAddress("BALANCER_POOL"));
            address owner = vm.envAddress("OWNER");
            uint16 multiplier = uint16(vm.envUint("ORACLE_MULTIPLIER"));
            uint56 secs = uint56(vm.envUint("ORACLE_SECS"));
            uint56 ago = uint56(vm.envUint("ORACLE_AGO"));
            uint128 minPrice = uint128(vm.envUint("ORACLE_MIN_PRICE"));
            oracle = new BalancerOracle(balancerPriceOracle, owner, multiplier, secs, ago, minPrice);
        }

        {
            string memory name = vm.envString("OT_NAME");
            string memory symbol = vm.envString("OT_SYMBOL");
            address owner = vm.envAddress("OWNER");
            address tokenAdmin = vm.envAddress("TOKEN_ADMIN");
            ERC20 paymentToken = ERC20(vm.envAddress("OT_PAYMENT_TOKEN"));
            IERC20Mintable underlyingToken = IERC20Mintable(vm.envAddress("OT_UNDERLYING_TOKEN"));
            address treasury = vm.envAddress("TREASURY");
            optionsToken =
                new OptionsToken(name, symbol, owner, tokenAdmin, paymentToken, underlyingToken, oracle, treasury);
        }

        vm.stopBroadcast();
    }
}
