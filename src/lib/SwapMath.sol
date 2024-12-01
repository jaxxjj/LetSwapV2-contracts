// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./FullMath.sol";
import "./SqrtPriceMath.sol";

/// @title Swap Math library for computing price and amount changes during swaps
/// @notice Contains functions for computing the result of a swap within a single tick price range
/// @dev Handles both exact input and exact output swaps, and calculates fees
library SwapMath {
    /// @notice Computes the result of swapping some amount in or out, within a single tick range
    /// @dev Calculates new sqrt price, input/output amounts, and fees for a swap step
    /// @param sqrtRatioCurrentX96 The current sqrt price of the pool
    /// @param sqrtRatioTargetX96 The price limit of the swap (target)
    /// @param liquidity The amount of usable liquidity
    /// @param amountRemaining How much input/output amount remains to be swapped
    /// @param feePips The fee taken from the input amount, in hundredths of a bip (1 bip = 0.01%)
    /// @return sqrtRatioNextX96 The price after swapping the amount in/out
    /// @return amountIn The amount to be provided by the msg.sender
    /// @return amountOut The amount to be received by the recipient
    /// @return feeAmount The amount of input tokens paid as protocol fee
    function computeSwapStep(
        uint160 sqrtRatioCurrentX96,
        uint160 sqrtRatioTargetX96,
        uint128 liquidity,
        int256 amountRemaining,
        uint24 feePips
    )
        internal
        pure
        returns (
            uint160 sqrtRatioNextX96,
            uint256 amountIn,
            uint256 amountOut,
            uint256 feeAmount
        )
    {
        // token 1 | token 0
        //  current tick
        //  <--- 0 for 1
        //       1 for 0 --->
        bool zeroForOne = sqrtRatioCurrentX96 >= sqrtRatioTargetX96;
        bool exactIn = amountRemaining >= 0;

        // Calculate max amount in or out and next sqrt ratio
        if (exactIn) {
            // Amount remaining - fee
            uint256 amountRemainingLessFee =
                FullMath.mulDiv(uint256(amountRemaining), 1e6 - feePips, 1e6);
            // Calculate max amount in, round up amount in
            amountIn = zeroForOne
                ? SqrtPriceMath.getAmount0Delta(
                    sqrtRatioTargetX96, sqrtRatioCurrentX96, liquidity, true
                )
                : SqrtPriceMath.getAmount1Delta(
                    sqrtRatioCurrentX96, sqrtRatioTargetX96, liquidity, true
                );
            // Calculate next sqrt ratio
            if (amountRemainingLessFee >= amountIn) {
                sqrtRatioNextX96 = sqrtRatioTargetX96;
            } else {
                // 0 for 1 = target < next <= current
                // 1 for 0 = current <= next < target
                sqrtRatioNextX96 = SqrtPriceMath.getNextSqrtPriceFromInput(
                    sqrtRatioCurrentX96,
                    liquidity,
                    amountRemainingLessFee,
                    zeroForOne
                );
            }
        } else {
            // Calculate max amount out, round down amount out
            amountOut = zeroForOne
                ? SqrtPriceMath.getAmount1Delta(
                    sqrtRatioTargetX96, sqrtRatioCurrentX96, liquidity, false
                )
                : SqrtPriceMath.getAmount0Delta(
                    sqrtRatioCurrentX96, sqrtRatioTargetX96, liquidity, false
                );
            // Calculate next sqrt ratio
            if (uint256(-amountRemaining) >= amountOut) {
                sqrtRatioNextX96 = sqrtRatioTargetX96;
            } else {
                // 0 for 1 = target < next <= current
                // 1 for 0 = current <= next < target
                sqrtRatioNextX96 = SqrtPriceMath.getNextSqrtPriceFromOutput(
                    sqrtRatioCurrentX96,
                    liquidity,
                    uint256(-amountRemaining),
                    zeroForOne
                );
            }
        }

        // Calculate amount in and out between sqrt current and next
        bool max = sqrtRatioTargetX96 == sqrtRatioNextX96;
        // max and exactIn   --> in  = amountIn
        //                       out = need to calculate
        // max and !exactIn  --> in  = need to calculate
        //                       out = amountOut
        // !max and exactIn  --> in  = need to calculate
        //                       out = need to calculate
        // !max and !exactIn --> in  = need to calculate
        //                       out = need to calculate
        if (zeroForOne) {
            amountIn = max && exactIn
                ? amountIn
                // Next <= current, round up amount in
                : SqrtPriceMath.getAmount0Delta(
                    sqrtRatioNextX96, sqrtRatioCurrentX96, liquidity, true
                );
            amountOut = max && !exactIn
                ? amountOut
                // Next <= current, round down amount out
                : SqrtPriceMath.getAmount1Delta(
                    sqrtRatioNextX96, sqrtRatioCurrentX96, liquidity, false
                );
        } else {
            amountIn = max && exactIn
                ? amountIn
                // Current <= next, round up amount in
                : SqrtPriceMath.getAmount1Delta(
                    sqrtRatioCurrentX96, sqrtRatioNextX96, liquidity, true
                );
            amountOut = max && !exactIn
                ? amountOut
                // Current <= next, round down amount out
                : SqrtPriceMath.getAmount0Delta(
                    sqrtRatioCurrentX96, sqrtRatioNextX96, liquidity, false
                );
        }

        // Cap the output amount to not exceed the remaining output amount
        if (!exactIn && amountOut > uint256(-amountRemaining)) {
            amountOut = uint256(-amountRemaining);
        }

        // Calculate fee on amount in
        if (exactIn && sqrtRatioNextX96 != sqrtRatioTargetX96) {
            // Take the remainder of the maximum input as fee
            feeAmount = uint256(amountRemaining) - amountIn;
        } else {
            // Not exact in or sqrt ratio next = target
            // - Not exact input
            // - Exact input and sqrt ratio next = target

            // a = amountIn
            // f = feePips
            // x = Amount in needed to put amountIn + fee
            // fee = x*f

            // Solve for x
            // x = a + fee = a + x*f
            // x*(1 - f) = a
            // x = a / (1 - f)

            // Calculate fee
            // fee = x*f = a / (1 - f) * f

            // fee = a * f / (1 - f)
            feeAmount =
                FullMath.mulDivRoundingUp(amountIn, feePips, 1e6 - feePips);
        }
    }
}
