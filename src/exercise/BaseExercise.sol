// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {IExercise} from "../interfaces/IExercise.sol";
import {IOptionsToken} from "../OptionsToken.sol";
import {SafeERC20} from "oz/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "oz/token/ERC20/IERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {Owned} from "solmate/auth/Owned.sol";

abstract contract BaseExercise is IExercise, Owned {
    using SafeERC20 for IERC20;
    using FixedPointMathLib for uint256;

    error Exercise__NotOToken();
    error Exercise__feeArrayLengthMismatch();
    error Exercise__InvalidFeeAmounts();

    event SetFees(address[] feeRecipients, uint256[] feeBPS);
    event DistributeFees(address[] feeRecipients, uint256[] feeBPS, uint256 totalAmount);

    uint256 public constant FEE_DENOMINATOR = 10_000;

    IOptionsToken public immutable oToken;

    /// @notice The fee addresses which receive any tokens paid during redemption
    address[] public feeRecipients;

    /// @notice The fee percentage in basis points, feeRecipients[n] receives
    /// feeBPS[n] * fee / 10_000 in fees
    uint256[] public feeBPS;

    constructor(IOptionsToken _oToken, address[] memory _feeRecipients, uint256[] memory _feeBPS) {
        oToken = _oToken;
        _setFees(_feeRecipients, _feeBPS);
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
    /// @dev Additional returns are reserved for future use
    function exercise(address from, uint256 amount, address recipient, bytes memory params)
        external
        virtual
        returns (uint256 paymentAmount, address, uint256, uint256);

    function setFees(address[] memory _feeRecipients, uint256[] memory _feeBPS) external onlyOwner {
        _setFees(_feeRecipients, _feeBPS);
    }

    function _setFees(address[] memory _feeRecipients, uint256[] memory _feeBPS) internal {
        if (_feeRecipients.length != _feeBPS.length) revert Exercise__feeArrayLengthMismatch();
        uint256 totalBPS = 0;
        for (uint256 i = 0; i < _feeBPS.length; i++) {
            totalBPS += _feeBPS[i];
        }
        if (totalBPS != FEE_DENOMINATOR) revert Exercise__InvalidFeeAmounts();
        feeRecipients = _feeRecipients;
        feeBPS = _feeBPS;
        emit SetFees(_feeRecipients, _feeBPS);
    }

    /// @notice Distributes fees to the fee recipients from a token holder who has approved
    /// @dev Sends the residual amount to the last fee recipient to avoid rounding errors
    function distributeFeesFrom(uint256 totalAmount, IERC20 token, address from) internal virtual {
        uint256 remaining = totalAmount;
        for (uint256 i = 0; i < feeRecipients.length - 1; i++) {
            uint256 feeAmount = totalAmount * feeBPS[i] / FEE_DENOMINATOR;
            token.safeTransferFrom(from, feeRecipients[i], feeAmount);
            remaining -= feeAmount;
        }
        token.safeTransferFrom(from, feeRecipients[feeRecipients.length - 1], remaining);
        emit DistributeFees(feeRecipients, feeBPS, totalAmount);
    }

    /// @notice Distributes fees to the fee recipients from token balance of exercise contract
    /// @dev Sends the residual amount to the last fee recipient to avoid rounding errors
    function distributeFees(uint256 totalAmount, IERC20 token) internal virtual {
        uint256 remaining = totalAmount;
        for (uint256 i = 0; i < feeRecipients.length - 1; i++) {
            uint256 feeAmount = totalAmount * feeBPS[i] / FEE_DENOMINATOR;
            token.safeTransfer(feeRecipients[i], feeAmount);
            remaining -= feeAmount;
        }
        token.safeTransfer(feeRecipients[feeRecipients.length - 1], remaining);
        emit DistributeFees(feeRecipients, feeBPS, totalAmount);
    }
}
