// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.20;
// Uni v3 core uses sol < 0.8 to suppress underflow / overflow

import "./SafeCast.sol";
import "./TickMath.sol";

/// @title Tick
/// @notice Contains functions for managing tick processes and storing per-tick data for Uniswap V3 pools
/// @dev Ticks are the price points at which liquidity can be added or removed.
///      Price between ticks is calculated using tick spacing.
///      Each tick represents a 0.01% price increase from the previous tick.
library Tick {
    using SafeCast for int256;

    /// @notice Stores information about each initialized tick
    /// @dev Each tick represents a price point where liquidity can be added/removed
    struct Info {
        /// @notice Total liquidity at this tick
        /// @dev Sum of all liquidityNet values added at this tick
        uint128 liquidityGross;

        /// @notice Amount of net liquidity change when tick is crossed
        /// @dev Positive when tick is crossed from left to right, negative when crossed from right to left
        int128 liquidityNet;

        /// @notice Fee growth per unit of liquidity on token0 outside the tick
        /// @dev Tracks fees accumulated outside the tick's price range
        uint256 feeGrowthOutside0X128;

        /// @notice Fee growth per unit of liquidity on token1 outside the tick
        /// @dev Tracks fees accumulated outside the tick's price range
        uint256 feeGrowthOutside1X128;

        /// @notice Whether the tick has been initialized
        /// @dev True if the tick has ever been used
        bool initialized;
    }

    /// @notice Calculates maximum liquidity per tick based on tick spacing
    /// @dev Prevents liquidity concentration attacks by enforcing a maximum amount per tick
    /// @param tickSpacing The spacing between usable ticks
    /// @return The maximum liquidity per tick
    function tickSpacingToMaxLiquidityPerTick(int24 tickSpacing)
        internal
        pure
        returns (uint128)
    {
        // Round down to a multiple of tick spacing
        int24 minTick = (TickMath.MIN_TICK / tickSpacing) * tickSpacing;
        int24 maxTick = (TickMath.MAX_TICK / tickSpacing) * tickSpacing;
        // Round up num ticks
        uint24 numTicks = uint24((maxTick - minTick) / tickSpacing) + 1;
        // Max liquidity = max(uint128) = 2**128 - 1
        // Max liquidity / num of ticks
        return type(uint128).max / numTicks;
    }

    /// @notice Calculates fee growth inside a tick range
    /// @dev Calculates fees accumulated within the range of tickLower to tickUpper
    /// @param self The mapping containing all tick information
    /// @param tickLower The lower tick boundary
    /// @param tickUpper The upper tick boundary
    /// @param tickCurrent The current tick
    /// @param feeGrowthGlobal0X128 The all-time global fee growth in token0
    /// @param feeGrowthGlobal1X128 The all-time global fee growth in token1
    /// @return feeGrowthInside0X128 The fee growth in token0 inside the tick range
    /// @return feeGrowthInside1X128 The fee growth in token1 inside the tick range
    function getFeeGrowthInside(
        mapping(int24 => Info) storage self,
        int24 tickLower,
        int24 tickUpper,
        int24 tickCurrent,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128
    )
        internal
        view
        returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128)
    {
        Info storage lower = self[tickLower];
        Info storage upper = self[tickUpper];

        unchecked {
            // Calculate fee growth below
            uint256 feeGrowthBelow0X128;
            uint256 feeGrowthBelow1X128;
            if (tickLower <= tickCurrent) {
                feeGrowthBelow0X128 = lower.feeGrowthOutside0X128;
                feeGrowthBelow1X128 = lower.feeGrowthOutside1X128;
            } else {
                feeGrowthBelow0X128 =
                    feeGrowthGlobal0X128 - lower.feeGrowthOutside0X128;
                feeGrowthBelow1X128 =
                    feeGrowthGlobal1X128 - lower.feeGrowthOutside1X128;
            }

            // Calculate fee growth above
            uint256 feeGrowthAbove0X128;
            uint256 feeGrowthAbove1X128;
            if (tickCurrent < tickUpper) {
                feeGrowthAbove0X128 = upper.feeGrowthOutside0X128;
                feeGrowthAbove1X128 = upper.feeGrowthOutside1X128;
            } else {
                feeGrowthAbove0X128 =
                    feeGrowthGlobal0X128 - upper.feeGrowthOutside0X128;
                feeGrowthAbove1X128 =
                    feeGrowthGlobal1X128 - upper.feeGrowthOutside1X128;
            }

            feeGrowthInside0X128 =
                feeGrowthGlobal0X128 - feeGrowthBelow0X128 - feeGrowthAbove0X128;
            feeGrowthInside1X128 =
                feeGrowthGlobal1X128 - feeGrowthBelow1X128 - feeGrowthAbove1X128;
        }
    }

    /// @notice Updates a tick and returns true if the tick was flipped from initialized to uninitialized or vice versa
    /// @dev Updates a tick's tracked liquidity and fee growth data
    /// @param self The mapping containing all tick information
    /// @param tick The tick to update
    /// @param tickCurrent The current tick
    /// @param liquidityDelta The amount of liquidity to add or remove
    /// @param feeGrowthGlobal0X128 The all-time global fee growth in token0
    /// @param feeGrowthGlobal1X128 The all-time global fee growth in token1
    /// @param upper Whether the tick is an upper tick for a position
    /// @param maxLiquidity The maximum liquidity allowed per tick
    /// @return flipped Whether the tick was flipped from initialized to uninitialized or vice versa
    function update(
        mapping(int24 => Info) storage self,
        int24 tick,
        int24 tickCurrent,
        int128 liquidityDelta,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128,
        bool upper,
        uint128 maxLiquidity
    ) internal returns (bool flipped) {
        Info storage info = self[tick];

        uint128 liquidityGrossBefore = info.liquidityGross;
        uint128 liquidityGrossAfter = liquidityDelta < 0
            ? liquidityGrossBefore - uint128(-liquidityDelta)
            : liquidityGrossBefore + uint128(liquidityDelta);

        require(liquidityGrossAfter <= maxLiquidity, "liquidity > max");

        // flipped = (liquidityGrossBefore == 0 && liquidityGrossAfter > 0)
        //     || (liquidityGrossBefore > 0 && liquidityGrossAfter == 0);

        flipped = (liquidityGrossBefore == 0) != (liquidityGrossAfter == 0);

        if (liquidityGrossBefore == 0) {
            // TODO: why initialize below tick?
            if (tick <= tickCurrent) {
                info.feeGrowthOutside0X128 = feeGrowthGlobal0X128;
                info.feeGrowthOutside1X128 = feeGrowthGlobal1X128;
            }
            info.initialized = true;
        }

        info.liquidityGross = liquidityGrossAfter;

        // lower    upper
        //   |       |
        //   +       -
        //   ----> one for zero +
        //   <---- zero for one -
        info.liquidityNet = upper
            ? info.liquidityNet - liquidityDelta
            : info.liquidityNet + liquidityDelta;
    }

    /// @notice Clears tick data
    /// @dev Deletes all the data associated with a tick
    /// @param self The mapping containing all tick information
    /// @param tick The tick to clear
    function clear(mapping(int24 => Info) storage self, int24 tick) internal {
        delete self[tick];
    }

    /// @notice Transitions tick data when the tick is crossed
    /// @dev Updates fee growth tracking data when price crosses a tick
    /// @param self The mapping containing all tick information
    /// @param tick The tick that was crossed
    /// @param feeGrowthGlobal0X128 The all-time global fee growth in token0
    /// @param feeGrowthGlobal1X128 The all-time global fee growth in token1
    /// @return liquidityNet The amount of liquidity added or removed when tick is crossed
    function cross(
        mapping(int24 => Info) storage self,
        int24 tick,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128
    ) internal returns (int128 liquidityNet) {
        Info storage info = self[tick];
        unchecked {
            info.feeGrowthOutside0X128 =
                feeGrowthGlobal0X128 - info.feeGrowthOutside0X128;
            info.feeGrowthOutside1X128 =
                feeGrowthGlobal1X128 - info.feeGrowthOutside1X128;
            liquidityNet = info.liquidityNet;
        }
    }
}