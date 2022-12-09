// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";

import {OptionsToken} from "../src/OptionsToken.sol";
import {CREATE3Script} from "./base/CREATE3Script.sol";
import {BalancerOracle} from "../src/oracles/BalancerOracle.sol";
import {IERC20Mintable} from "../src/interfaces/IERC20Mintable.sol";
import {IBalancerTwapOracle} from "../src/interfaces/IBalancerTwapOracle.sol";

contract DeployScript is CREATE3Script {
    constructor() CREATE3Script(vm.envString("VERSION")) {}

    function run() public returns (OptionsToken optionsToken, BalancerOracle oracle) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));

        vm.startBroadcast(deployerPrivateKey);

        {
            IBalancerTwapOracle balancerPriceOracle = IBalancerTwapOracle(vm.envAddress("BALANCER_POOL"));
            address owner = vm.envAddress("OWNER");
            uint16 multiplier = uint16(vm.envUint("ORACLE_MULTIPLIER"));
            uint56 secs = uint56(vm.envUint("ORACLE_SECS"));
            uint56 ago = uint56(vm.envUint("ORACLE_AGO"));
            uint128 minPrice = uint128(vm.envUint("ORACLE_MIN_PRICE"));

            oracle = BalancerOracle(
                create3.deploy(
                    getCreate3ContractSalt("BalancerOracle"),
                    bytes.concat(
                        type(BalancerOracle).creationCode,
                        abi.encode(balancerPriceOracle, owner, multiplier, secs, ago, minPrice)
                    )
                )
            );
        }

        {
            string memory name = vm.envString("OT_NAME");
            string memory symbol = vm.envString("OT_SYMBOL");
            address owner = vm.envAddress("OWNER");
            address tokenAdmin = getCreate3Contract("TokenAdmin");
            ERC20 paymentToken = ERC20(vm.envAddress("OT_PAYMENT_TOKEN"));
            IERC20Mintable underlyingToken = IERC20Mintable(getCreate3Contract("TimelessToken"));
            address treasury = vm.envAddress("TREASURY");
            bytes memory constructorParams =
                abi.encode(name, symbol, owner, tokenAdmin, paymentToken, underlyingToken, oracle, treasury);

            optionsToken = OptionsToken(
                create3.deploy(
                    getCreate3ContractSalt("OptionsToken"),
                    bytes.concat(type(OptionsToken).creationCode, constructorParams)
                )
            );
        }

        vm.stopBroadcast();
    }
}
