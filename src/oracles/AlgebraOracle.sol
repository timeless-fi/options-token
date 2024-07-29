// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {Owned} from "solmate/auth/Owned.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {IOracle} from "../interfaces/IOracle.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {IAlgebraPool} from "../interfaces/IAlgebraPool.sol";
import {TickMath} from "v3-core/libraries/TickMath.sol";
import {FullMath} from "v3-core/libraries/FullMath.sol";

/// @title Oracle using Algebra TWAP oracle as data source
/// @notice The oracle contract that provides the current price to purchase
/// the underlying token while exercising options. Uses Algebra TWAP oracle
/// as data source, and then applies a multiplier & lower bound.
/// @notice Same as UniswapV3, with a minimal interface change.
/// (observe -> getTimepoints)
contract AlgebraOracle is IOracle, Owned {
    /// -----------------------------------------------------------------------
    /// Library usage
    /// -----------------------------------------------------------------------

    using FixedPointMathLib for uint256;

    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    error AlgebraOracle__InvalidParams();
    error AlgebraOracle__InvalidWindow();
    error AlgebraOracle__BelowMinPrice();

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    event SetParams(uint56 secs, uint56 ago, uint128 minPrice);

    /// -----------------------------------------------------------------------
    /// Immutable parameters
    /// -----------------------------------------------------------------------

    uint256 internal constant MIN_SECS = 20 minutes;

    /// @notice The Algebra Pool contract (provides the oracle)
    IAlgebraPool public immutable algebraPool;

    /// -----------------------------------------------------------------------
    /// Storage variables
    /// -----------------------------------------------------------------------

    /// @notice The size of the window to take the TWAP value over in seconds.
    uint32 public secs;

    /// @notice The number of seconds in the past to take the TWAP from. The window
    /// would be (block.timestamp - secs - ago, block.timestamp - ago].
    uint32 public ago;

    /// @notice The minimum value returned by getPrice(). Maintains a floor for the
    /// price to mitigate potential attacks on the TWAP oracle.
    uint128 public minPrice;

    /// @notice Whether the price of token0 should be returned (in units of token1).
    /// If false, the price is returned in units of token0.
    bool public isToken0;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor(IAlgebraPool algebraPool_, address token, address owner_, uint32 secs_, uint32 ago_, uint128 minPrice_) Owned(owner_) {
        if (ERC20(algebraPool_.token0()).decimals() != 18 || ERC20(algebraPool_.token1()).decimals() != 18) revert AlgebraOracle__InvalidParams();
        if (algebraPool_.token0() != token && algebraPool_.token1() != token) revert AlgebraOracle__InvalidParams();
        if (secs_ < MIN_SECS) revert AlgebraOracle__InvalidWindow();
        algebraPool = algebraPool_;
        isToken0 = token == algebraPool_.token0();
        secs = secs_;
        ago = ago_;
        minPrice = minPrice_;

        emit SetParams(secs_, ago_, minPrice_);
    }

    /// -----------------------------------------------------------------------
    /// IOracle
    /// -----------------------------------------------------------------------

    /// @inheritdoc IOracle
    function getPrice() external view override returns (uint256 price) {
        /// -----------------------------------------------------------------------
        /// Validation
        /// -----------------------------------------------------------------------

        // The Algebra pool reverts on invalid TWAP queries, so we don't need to

        /// -----------------------------------------------------------------------
        /// Computation
        /// -----------------------------------------------------------------------

        // query Algebra oracle to get TWAP tick
        {
            uint32 _twapDuration = secs;
            uint32 _twapAgo = ago;
            uint32[] memory secondsAgo = new uint32[](2);
            secondsAgo[0] = _twapDuration + _twapAgo;
            secondsAgo[1] = _twapAgo;

            (int56[] memory tickCumulatives,,,) = algebraPool.getTimepoints(secondsAgo);
            int24 tick = int24((tickCumulatives[1] - tickCumulatives[0]) / int56(int32(_twapDuration)));

            uint256 decimalPrecision = 1e18;

            // from https://optimistic.etherscan.io/address/0xB210CE856631EeEB767eFa666EC7C1C57738d438#code#F5#L49
            uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(tick);

            // Calculate quoteAmount with better precision if it doesn't overflow when multiplied by itself
            if (sqrtRatioX96 <= type(uint128).max) {
                uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
                price = isToken0 ? FullMath.mulDiv(ratioX192, decimalPrecision, 1 << 192) : FullMath.mulDiv(1 << 192, decimalPrecision, ratioX192);
            } else {
                uint256 ratioX128 = FullMath.mulDiv(sqrtRatioX96, sqrtRatioX96, 1 << 64);
                price = isToken0 ? FullMath.mulDiv(ratioX128, decimalPrecision, 1 << 128) : FullMath.mulDiv(1 << 128, decimalPrecision, ratioX128);
            }
        }

        // apply minimum price
        if (price < minPrice) revert AlgebraOracle__BelowMinPrice();
    }

    /// @inheritdoc IOracle
    function getTokens() external view override returns (address paymentToken, address underlyingToken) {
        if (isToken0) {
            return (algebraPool.token1(), algebraPool.token0());
        } else {
            return (algebraPool.token0(), algebraPool.token1());
        }
    }

    /// -----------------------------------------------------------------------
    /// Owner functions
    /// -----------------------------------------------------------------------

    /// @notice Updates the oracle parameters. Only callable by the owner.
    /// @param secs_ The size of the window to take the TWAP value over in seconds.
    /// @param ago_ The number of seconds in the past to take the TWAP from. The window
    /// would be (block.timestamp - secs - ago, block.timestamp - ago].
    /// @param minPrice_ The minimum value returned by getPrice(). Maintains a floor for the
    /// price to mitigate potential attacks on the TWAP oracle.
    function setParams(uint32 secs_, uint32 ago_, uint128 minPrice_) external onlyOwner {
        if (secs_ < MIN_SECS) revert AlgebraOracle__InvalidWindow();
        secs = secs_;
        ago = ago_;
        minPrice = minPrice_;
        emit SetParams(secs_, ago_, minPrice_);
    }
}
