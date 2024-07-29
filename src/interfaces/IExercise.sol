// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

interface IExercise {
    /// @notice Exercise the options token
    /// @param from Address to exercise options tokens from.
    /// @param amount The amount of options tokens to exercise
    /// @param recipient The address that receives the underlying tokens
    /// @param params Additional parameters for the exercise
    /// @return paymentAmount The amount of underlying tokens to pay to the exercise contract
    /// @dev Additional returns are reserved for future use
    function exercise(address from, uint256 amount, address recipient, bytes memory params)
        external
        returns (uint256 paymentAmount, address, uint256, uint256);
}
