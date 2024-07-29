// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {Owned} from "solmate/auth/Owned.sol";
import {IERC20} from "oz/token/ERC20/IERC20.sol";
import {Pausable} from "oz/security/Pausable.sol";
import {SafeERC20} from "oz/token/ERC20/utils/SafeERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {BaseExercise} from "../exercise/BaseExercise.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {OptionsToken} from "../OptionsToken.sol";

import {ExchangeType, SwapProps, SwapHelper} from "../helpers/SwapHelper.sol";

struct DiscountExerciseParams {
    uint256 maxPaymentAmount;
    uint256 deadline;
    bool isInstantExit;
}

/// @title Options Token Exercise Contract
/// @author @lookee, @eidolon
/// @notice Contract that allows the holder of options tokens to exercise them,
/// in this case, by purchasing the underlying token at a discount to the market price.
/// @dev Assumes the underlying token and the payment token both use 18 decimals.
contract DiscountExercise is BaseExercise, SwapHelper, Pausable {
    /// Library usage
    using SafeERC20 for IERC20;
    using FixedPointMathLib for uint256;

    /// Errors
    error Exercise__SlippageTooHigh();
    error Exercise__PastDeadline();
    error Exercise__MultiplierOutOfRange();
    error Exercise__InvalidOracle();
    error Exercise__FeeGreaterThanMax();
    error Exercise__AmountOutIsZero();
    error Exercise__ZapMultiplierIncompatible();

    /// Events
    event Exercised(address indexed sender, address indexed recipient, uint256 amount, uint256 paymentAmount);
    event SetOracle(IOracle indexed newOracle);
    event SetTreasury(address indexed newTreasury);
    event SetMultiplier(uint256 indexed newMultiplier);
    event Claimed(uint256 indexed amount);
    event SetInstantFee(uint256 indexed instantFee);
    event SetMinAmountToTrigger(uint256 minAmountToTrigger);

    /// Constants
    /// Immutable parameters

    /// @notice The token paid by the options token holder during redemption
    IERC20 public immutable paymentToken;

    /// @notice The underlying token purchased during redemption
    IERC20 public immutable underlyingToken;

    /// Storage variables

    /// @notice The oracle contract that provides the current price to purchase
    /// the underlying token while exercising options (the strike price)
    IOracle public oracle;

    /// @notice The multiplier applied to the TWAP value. Encodes the discount of
    /// the options token. Uses 4 decimals.
    uint256 public multiplier;

    /// @notice The amount of payment tokens the user can claim
    /// Used when the contract does not have enough tokens to pay the user
    mapping(address => uint256) public credit;

    /// @notice The fee amount gathered in the contract to be swapped and distributed
    uint256 private feeAmount;

    /// @notice Minimal trigger to swap, if the trigger is not reached then feeAmount counts the ammount to swap and distribute
    uint256 public minAmountToTriggerSwap;

    /// @notice configurable parameter that determines what is the fee for zap (instant exit) feature
    uint256 public instantExitFee;

    constructor(
        OptionsToken oToken_,
        address owner_,
        IERC20 paymentToken_,
        IERC20 underlyingToken_,
        IOracle oracle_,
        uint256 multiplier_,
        uint256 instantExitFee_,
        uint256 minAmountToTriggerSwap_,
        address[] memory feeRecipients_,
        uint256[] memory feeBPS_,
        SwapProps memory swapProps_
    ) BaseExercise(oToken_, feeRecipients_, feeBPS_) Owned(owner_) SwapHelper() {
        paymentToken = paymentToken_;
        underlyingToken = underlyingToken_;

        _setSwapProps(swapProps_);
        _setOracle(oracle_);
        _setMultiplier(multiplier_);
        _setInstantExitFee(instantExitFee_);
        _setMinAmountToTriggerSwap(minAmountToTriggerSwap_);

        emit SetOracle(oracle_);
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
        whenNotPaused
        returns (uint256 paymentAmount, address, uint256, uint256)
    {
        DiscountExerciseParams memory _params = abi.decode(params, (DiscountExerciseParams));
        if (_params.isInstantExit) {
            return _zap(from, amount, recipient, _params);
        } else {
            return _redeem(from, amount, recipient, _params);
        }
    }

    /// @notice Transfers not claimed tokens to the sender.
    /// @dev When contract doesn't have funds during exercise, this function allows to claim the tokens once contract is funded
    /// @param to Destination address for token transfer
    function claim(address to) external whenNotPaused {
        uint256 amount = credit[msg.sender];
        if (amount == 0) return;
        credit[msg.sender] = 0;
        underlyingToken.safeTransfer(to, amount);
        emit Claimed(amount);
    }

    /// Owner functions
    function setSwapProps(SwapProps memory _swapProps) external virtual override onlyOwner {
        _setSwapProps(_swapProps);
    }

    /// @notice Sets the oracle contract. Only callable by the owner.
    /// @param oracle_ The new oracle contract
    function setOracle(IOracle oracle_) external onlyOwner {
        _setOracle(oracle_);
    }

    function _setOracle(IOracle oracle_) internal {
        (address paymentToken_, address underlyingToken_) = oracle_.getTokens();
        if (paymentToken_ != address(paymentToken) || underlyingToken_ != address(underlyingToken)) {
            revert Exercise__InvalidOracle();
        }
        oracle = oracle_;
        emit SetOracle(oracle_);
    }

    /// @notice Sets the discount multiplier.
    /// @param multiplier_ The new multiplier
    function setMultiplier(uint256 multiplier_) external onlyOwner {
        _setMultiplier(multiplier_);
    }

    function _setMultiplier(uint256 multiplier_) internal {
        if (
            multiplier_ > BPS_DENOM * 2 // over 200%
                || multiplier_ < BPS_DENOM / 10 // under 10%
        ) revert Exercise__MultiplierOutOfRange();
        multiplier = multiplier_;
        emit SetMultiplier(multiplier_);
    }

    /// @notice Sets the discount instantExitFee.
    /// @param _instantExitFee The new instantExitFee
    function setInstantExitFee(uint256 _instantExitFee) external onlyOwner {
        _setInstantExitFee(_instantExitFee);
    }

    function _setInstantExitFee(uint256 _instantExitFee) internal {
        if (_instantExitFee > BPS_DENOM) {
            revert Exercise__FeeGreaterThanMax();
        }
        instantExitFee = _instantExitFee;
        emit SetInstantFee(_instantExitFee);
    }

    /// @notice Sets the discount minAmountToTriggerSwap.
    /// @param _minAmountToTriggerSwap The new minAmountToTriggerSwap
    function setMinAmountToTriggerSwap(uint256 _minAmountToTriggerSwap) external onlyOwner {
        _setMinAmountToTriggerSwap(_minAmountToTriggerSwap);
    }

    function _setMinAmountToTriggerSwap(uint256 _minAmountToTriggerSwap) internal {
        minAmountToTriggerSwap = _minAmountToTriggerSwap;
        emit SetMinAmountToTrigger(_minAmountToTriggerSwap);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /// Internal functions
    function _zap(address from, uint256 amount, address recipient, DiscountExerciseParams memory params)
        internal
        returns (uint256 paymentAmount, address, uint256, uint256)
    {
        if (block.timestamp > params.deadline) revert Exercise__PastDeadline();
        if (multiplier >= BPS_DENOM) revert Exercise__ZapMultiplierIncompatible();
        uint256 discountedUnderlying = amount.mulDivUp(BPS_DENOM - multiplier, BPS_DENOM);
        uint256 fee = discountedUnderlying.mulDivUp(instantExitFee, BPS_DENOM);
        uint256 underlyingAmount = discountedUnderlying - fee;
        uint256 balance = underlyingToken.balanceOf(address(this));

        // Fee amount in underlying tokens charged for zapping
        feeAmount += fee;

        if (feeAmount >= minAmountToTriggerSwap && balance >= (feeAmount + underlyingAmount)) {
            uint256 minAmountOut = _getMinAmountOutData(feeAmount, swapProps.maxSwapSlippage, address(oracle));
            /* Approve the underlying token to make swap */
            underlyingToken.approve(swapProps.swapper, feeAmount);
            /* Swap underlying token to payment token (asset) */
            uint256 amountOut = _generalSwap(
                swapProps.exchangeTypes, address(underlyingToken), address(paymentToken), feeAmount, minAmountOut, swapProps.exchangeAddress
            );

            if (amountOut == 0) {
                revert Exercise__AmountOutIsZero();
            }

            feeAmount = 0;
            underlyingToken.approve(swapProps.swapper, 0);

            // transfer payment tokens from user to the set receivers
            distributeFees(paymentToken.balanceOf(address(this)), paymentToken);
        }

        // transfer underlying tokens to recipient without the bonus
        _pay(recipient, underlyingAmount);

        emit Exercised(from, recipient, underlyingAmount, paymentAmount);
    }

    /// Internal functions
    function _redeem(address from, uint256 amount, address recipient, DiscountExerciseParams memory params)
        internal
        virtual
        returns (uint256 paymentAmount, address, uint256, uint256)
    {
        if (block.timestamp > params.deadline) revert Exercise__PastDeadline();
        // apply multiplier to price
        paymentAmount = _getPaymentAmount(amount);
        if (paymentAmount > params.maxPaymentAmount) revert Exercise__SlippageTooHigh();
        // transfer payment tokens from user to the set receivers
        distributeFeesFrom(paymentAmount, paymentToken, from);
        // transfer underlying tokens to recipient
        _pay(recipient, amount);

        emit Exercised(from, recipient, amount, paymentAmount);
    }

    function _pay(address to, uint256 amount) internal returns (uint256 remainingAmount) {
        uint256 balance = underlyingToken.balanceOf(address(this));
        if (amount > balance) {
            underlyingToken.safeTransfer(to, balance);
            remainingAmount = amount - balance;
        } else {
            underlyingToken.safeTransfer(to, amount);
        }
        credit[to] += remainingAmount;
    }

    /// View functions

    /// @notice Returns the amount of payment tokens required to exercise the given amount of options tokens.
    /// @param amount The amount of options tokens to exercise
    function getPaymentAmount(uint256 amount) external view returns (uint256 paymentAmount) {
        return _getPaymentAmount(amount);
    }

    function _getPaymentAmount(uint256 amount) internal view returns (uint256 paymentAmount) {
        paymentAmount = amount.mulWadUp(oracle.getPrice().mulDivUp(multiplier, BPS_DENOM));
    }
}
