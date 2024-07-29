// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.13;

import {ISwapperSwaps, MinAmountOutData, MinAmountOutKind} from "vault-v2/ReaperSwapper.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

enum ExchangeType {
    UniV2,
    Bal,
    VeloSolid,
    UniV3
}

struct SwapProps {
    address swapper;
    address exchangeAddress;
    ExchangeType exchangeTypes;
    uint256 maxSwapSlippage;
}

abstract contract SwapHelper {
    using FixedPointMathLib for uint256;

    /// @notice The denominator for converting the multiplier into a decimal number.
    /// i.e. multiplier uses 4 decimals.
    uint256 internal constant BPS_DENOM = 10_000;
    SwapProps public swapProps;

    error SwapHelper__SlippageGreaterThanMax();
    error SwapHelper__ParamHasAddressZero();
    error SwapHelper__InvalidExchangeType(uint256 exType);

    constructor() {}

    /**
     * @dev Override function shall have proper access control
     * @param _swapProps - swap properties
     */
    function setSwapProps(SwapProps memory _swapProps) external virtual;

    function _setSwapProps(SwapProps memory _swapProps) internal {
        if (_swapProps.maxSwapSlippage > BPS_DENOM) {
            revert SwapHelper__SlippageGreaterThanMax();
        }
        if (_swapProps.exchangeAddress == address(0)) {
            revert SwapHelper__ParamHasAddressZero();
        }
        if (_swapProps.swapper == address(0)) {
            revert SwapHelper__ParamHasAddressZero();
        }
        swapProps = _swapProps;
    }

    /**
     *  @dev Private function that allow to swap via multiple exchange types
     *  @param exType - type of exchange
     *  @param tokenIn - address of token in
     *  @param tokenOut - address of token out
     *  @param amount - amount of tokenIn to swap
     *  @param minAmountOut - minimal acceptable amount of tokenOut
     *  @param exchangeAddress - address of the exchange
     */
    function _generalSwap(ExchangeType exType, address tokenIn, address tokenOut, uint256 amount, uint256 minAmountOut, address exchangeAddress)
        internal
        returns (uint256)
    {
        ISwapperSwaps _swapper = ISwapperSwaps(swapProps.swapper);
        MinAmountOutData memory minAmountOutData = MinAmountOutData(MinAmountOutKind.Absolute, minAmountOut);
        if (exType == ExchangeType.UniV2) {
            return _swapper.swapUniV2(tokenIn, tokenOut, amount, minAmountOutData, exchangeAddress);
        } else if (exType == ExchangeType.Bal) {
            return _swapper.swapBal(tokenIn, tokenOut, amount, minAmountOutData, exchangeAddress);
        } else if (exType == ExchangeType.VeloSolid) {
            return _swapper.swapVelo(tokenIn, tokenOut, amount, minAmountOutData, exchangeAddress);
        } else if (exType == ExchangeType.UniV3) {
            return _swapper.swapUniV3(tokenIn, tokenOut, amount, minAmountOutData, exchangeAddress);
        } else {
            revert SwapHelper__InvalidExchangeType(uint256(exType));
        }
    }

    /**
     * @dev Private function that calculates minimal amount token out of swap using oracles
     *  @param _amountIn - amount of token to be swapped
     *  @param _maxSlippage - max allowed slippage
     */
    function _getMinAmountOutData(uint256 _amountIn, uint256 _maxSlippage, address _oracle) internal view returns (uint256) {
        uint256 minAmountOut = 0;
        /* Get price from oracle */
        uint256 price = IOracle(_oracle).getPrice();
        /* Deduct slippage amount from predicted amount */
        minAmountOut = (_amountIn.mulWadUp(price) * (BPS_DENOM - _maxSlippage)) / BPS_DENOM;

        return minAmountOut;
    }
}
