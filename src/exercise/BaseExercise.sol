// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {IExercise} from "../interfaces/IExercise.sol";
import {OptionsToken} from "../OptionsToken.sol";

abstract contract BaseExercise is IExercise {
    error Exercise__NotOToken();

    OptionsToken public immutable oToken;

    constructor (OptionsToken _oToken) {
        oToken = _oToken;
    }

    modifier onlyOToken() {
        if (msg.sender != address(oToken)) revert Exercise__NotOToken();
        _;
    }

    /// @notice Called by the oToken and handles rewarding logic for the user.
    /// @dev *Must* have onlyOToken modifier.
    /// @param from Wallet that is exercising tokens
    /// @param amount Amount of tokens being exercised
    /// @param recipient Wallet that will receive the rewards for exercising the oTokens
    /// @param params Extraneous parameters that the function may use - abi.encoded struct
    function exercise(address from, uint256 amount, address recipient, bytes memory params)
        external
        virtual
        returns (bytes memory data);
}
