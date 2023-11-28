// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

interface IOptionsToken {
    function exercise(uint256 amount, address recipient, address option, bytes calldata params, uint256 deadline)
        external
        returns (bytes memory);

    function setOption(address _address, bool _isOption) external;

    function isOption(address) external returns (bool);
}
