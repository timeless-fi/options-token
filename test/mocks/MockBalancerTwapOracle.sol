// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.11;

import {IBalancerTwapOracle} from "../../src/interfaces/IBalancerTwapOracle.sol";
import {IVault} from "../../src/interfaces/IBalancerTwapOracle.sol";

contract MockVault is IVault {
    address[] tokens = new address[](2);

    constructor(address[] memory _tokens) {
        tokens = _tokens;
    }

    function joinPool(bytes32 poolId, address sender, address recipient, JoinPoolRequest memory request) external payable override {}

    function getPool(bytes32 poolId) external view override returns (address, PoolSpecialization) {}

    function getPoolTokens(bytes32 poolId) external view override returns (address[] memory tokens_, uint256[] memory, uint256) {
        tokens_ = new address[](2);
        tokens_[0] = tokens[0];
        tokens_[1] = tokens[1];
    }

    function swap(SingleSwap memory singleSwap, FundManagement memory funds, uint256 limit, uint256 deadline)
        external
        payable
        override
        returns (uint256)
    {}
}

contract MockBalancerTwapOracle is IBalancerTwapOracle {
    uint256 twapValue;
    IVault mockVault;

    constructor(address[] memory tokens) {
        mockVault = new MockVault(tokens);
    }

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

    function getLargestSafeQueryWindow() external pure override returns (uint256) {
        return 24 hours; // simulates an oracle that can look back at most 24 hours
    }

    function getPastAccumulators(IBalancerTwapOracle.OracleAccumulatorQuery[] memory queries)
        external
        view
        override
        returns (int256[] memory results)
    {}

    function getLatest(IBalancerTwapOracle.Variable variable) external view override returns (uint256) {}

    function getVault() external view override returns (IVault) {
        return mockVault;
    }

    function getPoolId() external view override returns (bytes32) {}
}
