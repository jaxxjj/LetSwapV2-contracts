// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.20;

import "./FullMath.sol";
import "./FixedPoint128.sol";

/// @title Position
/// @notice Positions represent an owner's liquidity between a lower and upper tick boundary
/// @dev Positions store additional state for tracking fees owed to the position
library Position {
    /// @notice Position state holding the liquidity amount and fee growth data
    /// @dev Packed for gas efficiency - uses uint128 where possible
    struct Info {
        /// @notice The amount of liquidity owned by this position
        uint128 liquidity;
        /// @notice Fee growth per unit of liquidity for token0, as of last position update
        /// @dev Stored as a Q128.128 fixed point number
        uint256 feeGrowthInside0LastX128;
        /// @notice Fee growth per unit of liquidity for token1, as of last position update
        /// @dev Stored as a Q128.128 fixed point number
        uint256 feeGrowthInside1LastX128;
        /// @notice Uncollected token0 fees owed to the position owner
        uint128 tokensOwed0;
        /// @notice Uncollected token1 fees owed to the position owner
        uint128 tokensOwed1;
    }

    /// @notice Returns the Info struct for a given position
    /// @param self The mapping containing all position information
    /// @param owner The address of the position owner
    /// @param tickLower The lower tick boundary of the position
    /// @param tickUpper The upper tick boundary of the position
    /// @return position The position info struct for this owner and tick range
    function get(
        mapping(bytes32 => Info) storage self,
        address owner,
        int24 tickLower,
        int24 tickUpper
    ) internal view returns (Info storage position) {
        position =
            self[keccak256(abi.encodePacked(owner, tickLower, tickUpper))];
    }

    /// @notice Updates a position with new liquidity and fee growth data
    /// @dev Calculates fees owed and updates position state
    /// @param self The position to update
    /// @param liquidityDelta The change in liquidity (positive for increase, negative for decrease)
    /// @param feeGrowthInside0X128 The all-time fee growth in token0, per unit of liquidity, inside the position's tick range
    /// @param feeGrowthInside1X128 The all-time fee growth in token1, per unit of liquidity, inside the position's tick range
    function update(
        Info storage self,
        int128 liquidityDelta,
        uint256 feeGrowthInside0X128,
        uint256 feeGrowthInside1X128
    ) internal {
        Info memory _self = self;

        if (liquidityDelta == 0) {
            // disallow pokes for 0 liquidity positions
            require(_self.liquidity > 0);
        }

        // Calculate fees
        uint128 tokensOwed0 = uint128(
            FullMath.mulDiv(
                feeGrowthInside0X128 - _self.feeGrowthInside0LastX128,
                _self.liquidity,
                FixedPoint128.Q128
            )
        );
        uint128 tokensOwed1 = uint128(
            FullMath.mulDiv(
                feeGrowthInside1X128 - _self.feeGrowthInside1LastX128,
                _self.liquidity,
                FixedPoint128.Q128
            )
        );

        if (liquidityDelta != 0) {
            self.liquidity = liquidityDelta < 0
                ? _self.liquidity - uint128(-liquidityDelta)
                : _self.liquidity + uint128(liquidityDelta);
        }
        if (tokensOwed0 > 0 || tokensOwed1 > 0) {
            self.tokensOwed0 += tokensOwed0;
            self.tokensOwed1 += tokensOwed1;
        }
    }
}