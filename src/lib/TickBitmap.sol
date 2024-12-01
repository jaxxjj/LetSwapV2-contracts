// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.20;

import "./BitMath.sol";

/// @title Tick Bitmap Library for tracking initialized ticks
/// @notice Stores a packed mapping of tick indexes to booleans for gas-efficient tick tracking
/// @dev Used for finding the next initialized tick in either direction
library TickBitmap {
    /// @notice Calculates word position and bit position within the word for a given tick
    /// @dev A tick is converted into a position in the bitmap using index math
    /// @param tick The tick for which to compute the position
    /// @return wordPos The key in the mapping containing the word in which the bit is stored
    /// @return bitPos The bit position in the word where the flag is stored
    function position(int24 tick)
        private
        pure
        returns (int16 wordPos, uint8 bitPos)
    {
        // Shift right last 8 bits
        wordPos = int16(tick >> 8);
        // Last 8 bits
        bitPos = uint8(uint24(tick % 256));
    }
    /// @notice Flips the initialized state for a given tick from false to true, or vice versa
    /// @param self The mapping in which to flip the tick
    /// @param tick The tick to flip
    /// @param tickSpacing The spacing between usable ticks
    function flipTick(
        mapping(int16 => uint256) storage self,
        int24 tick,
        int24 tickSpacing
    ) internal {
        require(tick % tickSpacing == 0);
        (int16 wordPos, uint8 bitPos) = position(tick / tickSpacing);
        // 0 <= uint8 <= 2**8 - 1 = 255
        // mask = 1 at bit position, rest are 0
        uint256 mask = 1 << bitPos;
        // xor
        self[wordPos] ^= mask;
    }

    /// @notice Finds the next initialized tick in word (shifted left by tickSpacing) or returns tick beyond current word
    /// @param self The mapping in which to compute the next initialized tick
    /// @param tick The starting tick
    /// @param tickSpacing The spacing between usable ticks
    /// @param lte Whether to search for the next initialized tick to the left (less than or equal to the starting tick)
    /// @return next The next initialized or uninitialized tick up to 256 ticks away from the current tick
    /// @return initialized Whether the next tick is initialized, as the function only searches within up to 256 ticks
    function nextInitializedTickWithinOneWord(
        mapping(int16 => uint256) storage self,
        int24 tick,
        int24 tickSpacing,
        // true = seatch to the left
        bool lte
    ) internal view returns (int24 next, bool initialized) {
        int24 compressed = tick / tickSpacing;
        // Round down to negative infinity
        if (tick < 0 && tick % tickSpacing != 0) {
            compressed--;
        }

        if (lte) {
            // Search lesser or equal tick = bit to the right of current bit position
            (int16 wordPos, uint8 bitPos) = position(compressed);

            // All 1s at or to the right of bitPos
            uint256 mask = (1 << bitPos) - 1 + (1 << bitPos);
            uint256 masked = self[wordPos] & mask;

            initialized = masked != 0;

            // nect = (compressed - remove bit pos + right most bit of masked) * tick spacing
            //      = (compressed - bit pos        + msb(masked)) * tick spacing
            next = initialized
                ? (
                    compressed
                        - int24(uint24(bitPos - BitMath.mostSignificantBit(masked)))
                ) * tickSpacing
                : (compressed - int24(uint24(bitPos))) * tickSpacing;
        } else {
            // Search greater tick = bit to the left of current bit position
            // Start search from next tick
            (int16 wordPos, uint8 bitPos) = position(compressed + 1);
            // All 1s at or to the left of bitPos
            // 1 << bitPos = 1 at bitPos
            // (1 << bitPos) - 1 = All 1s to the right of bitPos
            // ~((1 << bit) - 1) = All 1s at or to the left of bitPos
            uint256 mask = ~((1 << bitPos) - 1);
            uint256 masked = self[wordPos] & mask;

            initialized = masked != 0;

            // next = (next compressed tick + left most bit of masked  - remove bit pos) * tick spacing
            //      = (compressed + 1       + lsb(masked)              - bit pos) * tick spacing
            next = initialized
                ? (
                    compressed + 1
                        + int24(uint24(BitMath.leastSignificantBit(masked) - bitPos))
                ) * tickSpacing
                : (compressed + 1 + int24(uint24(type(uint8).max - bitPos)))
                    * tickSpacing;
        }
    }
}
