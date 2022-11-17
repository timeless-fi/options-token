// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.11;

import {IBalancerTwapOracle} from "../../src/interfaces/IBalancerTwapOracle.sol";

contract MockBalancerTwapOracle is IBalancerTwapOracle {
    uint256 twapValue;

    function setTwapValue(uint256 value) external {
        twapValue = value;
    }

    function getTimeWeightedAverage(IBalancerTwapOracle.OracleAverageQuery[] memory queries)
        external
        view
        override
        returns (uint256[] memory results)
    {
        queries;
        results = new uint256[](1);
        results[0] = twapValue;
    }

    function getLatest(IBalancerTwapOracle.Variable variable) external view override returns (uint256) {
        // not implemented
    }

    function getLargestSafeQueryWindow() external pure override returns (uint256) {
        return 24 hours; // simulates an oracle that can look back at most 24 hours
    }

    function getPastAccumulators(IBalancerTwapOracle.OracleAccumulatorQuery[] memory queries)
        external
        view
        override
        returns (int256[] memory results)
    {
        // not implemented
    }
}
