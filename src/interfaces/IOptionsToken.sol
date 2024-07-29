// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {IERC20Mintable} from "./IERC20Mintable.sol";

interface IOptionsToken is IERC20Mintable {
    function exercise(uint256 amount, address recipient, address option, bytes calldata params)
        external
        returns (uint256 paymentAmount, address, uint256, uint256);

    function setExerciseContract(address _address, bool _isExercise) external;

    function isExerciseContract(address) external returns (bool);
}
