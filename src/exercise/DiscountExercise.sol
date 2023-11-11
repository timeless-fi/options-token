// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {Owned} from "solmate/auth/Owned.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {BaseExercise} from "../exercise/BaseExercise.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {IERC20Mintable} from "../interfaces/IERC20Mintable.sol";
import {OptionsToken} from "../OptionsToken.sol";

struct DiscountExerciseParams {
    uint256 maxPaymentAmount;
}

struct DiscountExerciseReturnData {
    uint256 paymentAmount;
}

/// @title Options Token Exercise Contract
/// @author @bigbadbeard, @lookee, @eidolon
/// @notice Contract that allows the holder of options tokens to exercise them,
/// in this case, by purchasing the underlying token at a discount to the market price.
/// @dev Assumes the underlying token and the payment token both use 18 decimals.
contract DiscountExercise is BaseExercise, Owned {
    /// Library usage
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /// Errors
    error Exercise__SlippageTooHigh();

    /// Events
    event Exercised(address indexed sender, address indexed recipient, uint256 amount, uint256 paymentAmount);
    event SetOracle(IOracle indexed newOracle);
    event SetTreasury(address indexed newTreasury);

    /// Immutable parameters

    /// @notice The token paid by the options token holder during redemption
    ERC20 public immutable paymentToken;

    /// @notice The underlying token purchased during redemption
    IERC20Mintable public immutable underlyingToken;

    /// Storage variables

    /// @notice The oracle contract that provides the current price to purchase
    /// the underlying token while exercising options (the strike price)
    IOracle public oracle;

    /// @notice The treasury address which receives tokens paid during redemption
    address public treasury;

    constructor(
        OptionsToken oToken_,
        address owner_,
        ERC20 paymentToken_,
        IERC20Mintable underlyingToken_,
        IOracle oracle_,
        address treasury_
    ) BaseExercise(oToken_) Owned(owner_) {
        paymentToken = paymentToken_;
        underlyingToken = underlyingToken_;
        oracle = oracle_;
        treasury = treasury_;

        emit SetOracle(oracle_);
        emit SetTreasury(treasury_);
    }

    /// External functions

    /// @notice Exercises options tokens to purchase the underlying tokens.
    /// @dev The oracle may revert if it cannot give a secure result.
    /// @param from The user that is exercising their options tokens
    /// @param amount The amount of options tokens to exercise
    /// @param recipient The recipient of the purchased underlying tokens
    /// @param params Extra parameters to be used by the exercise function
    function exercise(address from, uint256 amount, address recipient, bytes memory params)
        external
        virtual
        override
        onlyOToken
        returns (bytes memory data)
    {
        if (msg.sender != address(oToken)) revert Exercise__NotOToken();
        return _exercise(from, amount, recipient, params);
    }

    /// Owner functions

    /// @notice Sets the oracle contract. Only callable by the owner.
    /// @param oracle_ The new oracle contract
    function setOracle(IOracle oracle_) external onlyOwner {
        oracle = oracle_;
        emit SetOracle(oracle_);
    }

    /// @notice Sets the treasury address. Only callable by the owner.
    /// @param treasury_ The new treasury address
    function setTreasury(address treasury_) external onlyOwner {
        treasury = treasury_;
        emit SetTreasury(treasury_);
    }

    /// Internal functions

    function _exercise(address from, uint256 amount, address recipient, bytes memory params)
        internal
        virtual
        returns (bytes memory data)
    {
        // decode params
        DiscountExerciseParams memory _params = abi.decode(params, (DiscountExerciseParams));

        // transfer payment tokens from user to the treasury
        uint256 paymentAmount = amount.mulWadUp(oracle.getPrice());
        if (paymentAmount > _params.maxPaymentAmount) revert Exercise__SlippageTooHigh();
        paymentToken.safeTransferFrom(from, treasury, paymentAmount);

        // mint underlying tokens to recipient
        underlyingToken.mint(recipient, amount);

        data = abi.encode(
            DiscountExerciseReturnData({
                paymentAmount: paymentAmount
            })
        );

        emit Exercised(from, recipient, amount, paymentAmount);
    }
}
