// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import "../interfaces/IBalancerTwapOracle.sol";

interface IBalancer2TokensPool is IBalancerTwapOracle {
    function getNormalizedWeights() external view returns (uint256[] memory);
}
