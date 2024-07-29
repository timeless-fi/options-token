// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {Owned} from "solmate/auth/Owned.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {IThenaPair} from "../interfaces/IThenaPair.sol";

/// @title Oracle using Thena TWAP oracle as data source
/// @author zefram.eth/lookee/Eidolon
/// @notice The oracle contract that provides the current price to purchase
/// the underlying token while exercising options. Uses Thena TWAP oracle
/// as data source, and then applies a lower bound.
contract ThenaOracle is IOracle, Owned {
    /// -----------------------------------------------------------------------
    /// Library usage
    /// -----------------------------------------------------------------------

    using FixedPointMathLib for uint256;

    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    error ThenaOracle__InvalidParams();
    error ThenaOracle__InvalidWindow();
    error ThenaOracle__StablePairsUnsupported();
    error ThenaOracle__Overflow();
    error ThenaOracle__BelowMinPrice();

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    event SetParams(uint56 secs, uint128 minPrice);

    /// -----------------------------------------------------------------------
    /// Immutable parameters
    /// -----------------------------------------------------------------------

    uint256 internal constant MIN_SECS = 20 minutes;

    /// @notice The Thena TWAP oracle contract (usually a pool with oracle support)
    IThenaPair public immutable thenaPair;

    /// -----------------------------------------------------------------------
    /// Storage variables
    /// -----------------------------------------------------------------------

    /// @notice The size of the window to take the TWAP value over in seconds.
    uint56 public secs;

    /// @notice The minimum value returned by getPrice(). Maintains a floor for the
    /// price to mitigate potential attacks on the TWAP oracle.
    uint128 public minPrice;

    /// @notice Whether the price should be returned in terms of token0.
    /// If false, the price is returned in terms of token1.
    bool public isToken0;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor(IThenaPair thenaPair_, address token, address owner_, uint56 secs_, uint128 minPrice_) Owned(owner_) {
        if (ERC20(thenaPair_.token0()).decimals() != 18 || ERC20(thenaPair_.token1()).decimals() != 18) revert ThenaOracle__InvalidParams();
        if (thenaPair_.stable()) revert ThenaOracle__StablePairsUnsupported();
        if (thenaPair_.token0() != token && thenaPair_.token1() != token) revert ThenaOracle__InvalidParams();
        if (secs_ < MIN_SECS) revert ThenaOracle__InvalidWindow();

        thenaPair = thenaPair_;
        isToken0 = thenaPair_.token0() == token;
        secs = secs_;
        minPrice = minPrice_;

        emit SetParams(secs_, minPrice_);
    }

    /// -----------------------------------------------------------------------
    /// IOracle
    /// -----------------------------------------------------------------------

    /// @inheritdoc IOracle
    function getPrice() external view override returns (uint256 price) {
        /// -----------------------------------------------------------------------
        /// Storage loads
        /// -----------------------------------------------------------------------

        uint256 secs_ = secs;

        /// -----------------------------------------------------------------------
        /// Computation
        /// -----------------------------------------------------------------------

        // query Thena oracle to get TWAP value
        {
            (uint256 reserve0CumulativeCurrent, uint256 reserve1CumulativeCurrent, uint256 blockTimestampCurrent) =
                thenaPair.currentCumulativePrices();
            uint256 observationLength = IThenaPair(thenaPair).observationLength();
            (uint256 blockTimestampLast, uint256 reserve0CumulativeLast, uint256 reserve1CumulativeLast) =
                thenaPair.observations(observationLength - 1);
            uint32 T = uint32(blockTimestampCurrent - blockTimestampLast);
            if (T < secs_) {
                (blockTimestampLast, reserve0CumulativeLast, reserve1CumulativeLast) = thenaPair.observations(observationLength - 2);
                T = uint32(blockTimestampCurrent - blockTimestampLast);
            }
            uint112 reserve0 = safe112((reserve0CumulativeCurrent - reserve0CumulativeLast) / T);
            uint112 reserve1 = safe112((reserve1CumulativeCurrent - reserve1CumulativeLast) / T);

            if (!isToken0) {
                price = uint256(reserve0).divWadDown(reserve1);
            } else {
                price = uint256(reserve1).divWadDown(reserve0);
            }
        }

        if (price < minPrice) revert ThenaOracle__BelowMinPrice();
    }

    /// @inheritdoc IOracle
    function getTokens() external view override returns (address paymentToken, address underlyingToken) {
        if (isToken0) {
            return (thenaPair.token1(), thenaPair.token0());
        } else {
            return (thenaPair.token0(), thenaPair.token1());
        }
    }

    /// -----------------------------------------------------------------------
    /// Owner functions
    /// -----------------------------------------------------------------------

    /// @notice Updates the oracle parameters. Only callable by the owner.
    /// @param secs_ The size of the window to take the TWAP value over in seconds.
    /// @param minPrice_ The minimum value returned by getPrice(). Maintains a floor for the
    /// price to mitigate potential attacks on the TWAP oracle.
    function setParams(uint56 secs_, uint128 minPrice_) external onlyOwner {
        if (secs_ < MIN_SECS) revert ThenaOracle__InvalidWindow();
        secs = secs_;
        minPrice = minPrice_;
        emit SetParams(secs_, minPrice_);
    }

    /// -----------------------------------------------------------------------
    /// Util functions
    /// -----------------------------------------------------------------------

    function safe112(uint256 n) internal pure returns (uint112) {
        if (n >= 2 ** 112) revert ThenaOracle__Overflow();
        return uint112(n);
    }
}
