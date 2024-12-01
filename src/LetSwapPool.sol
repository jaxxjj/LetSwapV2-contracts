// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.20;

import "./interfaces/IERC20.sol";
import "./lib/SafeCast.sol";
import "./lib/TickMath.sol";
import "./lib/Position.sol";
import "./lib/Tick.sol";
import "./lib/TickBitmap.sol";
import "./lib/SqrtPriceMath.sol";
import "./lib/SwapMath.sol";
import "./lib/FullMath.sol";
import "./lib/FixedPoint128.sol";

// slot 0 = 32 bytes
// 2**256 = 32 bytes
struct Slot0 {
    // 160 / 8 = 20 bytes
    uint160 sqrtPriceX96;
    // 24 / 8 = 3 bytes
    int24 tick;
    // 1 byte
    bool unlocked;
}

function checkTicks(int24 tickLower, int24 tickUpper) pure {
    require(tickLower < tickUpper);
    require(TickMath.MIN_TICK <= tickLower);
    require(tickUpper <= TickMath.MAX_TICK);
}

/// @title Automated market maker pool
/// @notice Manages liquidity positions and executes swaps between two ERC20 tokens
contract LetSwapPool {
    using SafeCast for uint256;
    using SafeCast for int256;
    using Tick for mapping(int24 => Tick.Info);
    using TickBitmap for mapping(int16 => uint256);
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;

    address public immutable token0;
    address public immutable token1;
    // 0.1% = 1000
    uint24 public immutable fee;
    int24 public immutable tickSpacing;
    uint128 public immutable maxLiquidityPerTick;

    Slot0 public slot0;
    uint256 public feeGrowthGlobal0X128;
    uint256 public feeGrowthGlobal1X128;
    uint128 public liquidity;
    mapping(int24 => Tick.Info) public ticks;
    mapping(int16 => uint256) public tickBitmap;
    mapping(bytes32 => Position.Info) public positions;

    modifier lock() {
        require(slot0.unlocked, "locked");
        slot0.unlocked = false;
        _;
        slot0.unlocked = true;
    }

    /// @notice Creates a new pool with the specified tokens and fee
    /// @param _token0 The contract address of the first token
    /// @param _token1 The contract address of the second token
    /// @param _fee The fee collected upon every swap in the pool, denominated in hundredths of a bip
    /// @param _tickSpacing The minimum number of ticks between initialized ticks
    constructor(
        address _token0,
        address _token1,
        uint24 _fee,
        int24 _tickSpacing
    ) {
        require(_token0 != address(0), "token 0 = zero address");
        require(_token0 < _token1, "token 0 >= token 1");

        token0 = _token0;
        token1 = _token1;
        fee = _fee;
        tickSpacing = _tickSpacing;
        maxLiquidityPerTick = Tick.tickSpacingToMaxLiquidityPerTick(tickSpacing);
    }

    /// @notice Sets the initial price for the pool
    /// @param sqrtPriceX96 The initial sqrt price of the pool as a Q64.96
    function initialize(uint160 sqrtPriceX96) external {
        require(slot0.sqrtPriceX96 == 0, "already initialized");
        int24 tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
        slot0 = Slot0({sqrtPriceX96: sqrtPriceX96, tick: tick, unlocked: true});
    }

    struct ModifyPositionParams {
        address owner;
        int24 tickLower;
        int24 tickUpper;
        int128 liquidityDelta;
    }

    function _modifyPosition(ModifyPositionParams memory params)
        private
        returns (Position.Info storage position, int256 amount0, int256 amount1)
    {
        checkTicks(params.tickLower, params.tickUpper);

        Slot0 memory _slot0 = slot0;

        position = _updatePosition(
            params.owner,
            params.tickLower,
            params.tickUpper,
            params.liquidityDelta,
            _slot0.tick
        );

        // Get amount 0 and amount 1
        // token 1 | token 0
        // --------|---------
        //        tick
        if (params.liquidityDelta != 0) {
            if (_slot0.tick < params.tickLower) {
                // Calculate amount 0
                amount0 = SqrtPriceMath.getAmount0Delta(
                    TickMath.getSqrtRatioAtTick(params.tickLower),
                    TickMath.getSqrtRatioAtTick(params.tickUpper),
                    params.liquidityDelta
                );
            } else if (_slot0.tick < params.tickUpper) {
                // Calculate amount 0 and amount 1
                amount0 = SqrtPriceMath.getAmount0Delta(
                    _slot0.sqrtPriceX96,
                    TickMath.getSqrtRatioAtTick(params.tickUpper),
                    params.liquidityDelta
                );
                amount1 = SqrtPriceMath.getAmount1Delta(
                    TickMath.getSqrtRatioAtTick(params.tickLower),
                    _slot0.sqrtPriceX96,
                    params.liquidityDelta
                );

                liquidity = params.liquidityDelta < 0
                    ? liquidity - uint128(-params.liquidityDelta)
                    : liquidity + uint128(params.liquidityDelta);
            } else {
                // Calculate amount 1
                amount1 = SqrtPriceMath.getAmount1Delta(
                    TickMath.getSqrtRatioAtTick(params.tickLower),
                    TickMath.getSqrtRatioAtTick(params.tickUpper),
                    params.liquidityDelta
                );
            }
        }
    }

    function _updatePosition(
        address owner,
        int24 tickLower,
        int24 tickUpper,
        int128 liquidityDelta,
        int24 tick
    ) private returns (Position.Info storage position) {
        position = positions.get(owner, tickLower, tickUpper);

        uint256 _feeGrowthGlobal0X128 = feeGrowthGlobal0X128;
        uint256 _feeGrowthGlobal1X128 = feeGrowthGlobal1X128;

        bool flippedLower;
        bool flippedUpper;
        if (liquidityDelta != 0) {
            flippedLower = ticks.update(
                tickLower,
                tick,
                liquidityDelta,
                _feeGrowthGlobal0X128,
                _feeGrowthGlobal1X128,
                false,
                maxLiquidityPerTick
            );
            flippedUpper = ticks.update(
                tickUpper,
                tick,
                liquidityDelta,
                _feeGrowthGlobal0X128,
                _feeGrowthGlobal1X128,
                true,
                maxLiquidityPerTick
            );

            if (flippedLower) {
                tickBitmap.flipTick(tickLower, tickSpacing);
            }
            if (flippedUpper) {
                tickBitmap.flipTick(tickUpper, tickSpacing);
            }
        }

        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = ticks
            .getFeeGrowthInside(
            tickLower,
            tickUpper,
            tick,
            _feeGrowthGlobal0X128,
            _feeGrowthGlobal1X128
        );

        position.update(
            liquidityDelta, feeGrowthInside0X128, feeGrowthInside1X128
        );

        // Liquidity decreased and tick was flipped = liquidity after is 0
        if (liquidityDelta < 0) {
            if (flippedLower) {
                ticks.clear(tickLower);
            }
            if (flippedUpper) {
                ticks.clear(tickUpper);
            }
        }
    }

    /// @notice Adds liquidity for the given price range
    /// @param recipient The address that will receive the liquidity position
    /// @param tickLower The lower tick of the position
    /// @param tickUpper The upper tick of the position
    /// @param amount The amount of liquidity to mint
    /// @return amount0 The amount of token0 sent to the pool
    /// @return amount1 The amount of token1 sent to the pool
    function mint(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount
    ) external lock returns (uint256 amount0, uint256 amount1) {
        require(amount > 0, "amount = 0");

        (, int256 amount0Int, int256 amount1Int) = _modifyPosition(
            ModifyPositionParams({
                owner: recipient,
                tickLower: tickLower,
                tickUpper: tickUpper,
                // 0 < amount <= max int128 = 2**127 - 1
                liquidityDelta: int256(uint256(amount)).toInt128()
            })
        );

        amount0 = uint256(amount0Int);
        amount1 = uint256(amount1Int);

        if (amount0 > 0) {
            IERC20(token0).transferFrom(msg.sender, address(this), amount0);
        }
        if (amount1 > 0) {
            IERC20(token1).transferFrom(msg.sender, address(this), amount1);
        }
    }

    /// @notice Collects tokens owed to a position
    /// @param recipient The address that will receive the collected tokens
    /// @param tickLower The lower tick of the position
    /// @param tickUpper The upper tick of the position
    /// @param amount0Requested How much token0 should be withdrawn from the fees owed
    /// @param amount1Requested How much token1 should be withdrawn from the fees owed
    /// @return amount0 The amount of token0 collected
    /// @return amount1 The amount of token1 collected
    function collect(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external lock returns (uint128 amount0, uint128 amount1) {
        Position.Info storage position =
            positions.get(msg.sender, tickLower, tickUpper);

        // min(amount owed, amount request)
        amount0 = amount0Requested > position.tokensOwed0
            ? position.tokensOwed0
            : amount0Requested;
        amount1 = amount1Requested > position.tokensOwed1
            ? position.tokensOwed1
            : amount1Requested;

        if (amount0 > 0) {
            position.tokensOwed0 -= amount0;
            IERC20(token0).transfer(recipient, amount0);
        }
        if (amount1 > 0) {
            position.tokensOwed1 -= amount1;
            IERC20(token1).transfer(recipient, amount1);
        }
    }

    /// @notice Burn liquidity from the sender's position
    /// @param tickLower The lower tick of the position
    /// @param tickUpper The upper tick of the position
    /// @param amount The amount of liquidity to burn
    /// @return amount0 The amount of token0 sent to the recipient
    /// @return amount1 The amount of token1 sent to the recipient
    function burn(int24 tickLower, int24 tickUpper, uint128 amount)
        external
        lock
        returns (uint256 amount0, uint256 amount1)
    {
        (Position.Info storage position, int256 amount0Int, int256 amount1Int) =
        _modifyPosition(
            ModifyPositionParams({
                owner: msg.sender,
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: -int256(uint256(amount)).toInt128()
            })
        );

        amount0 = uint256(-amount0Int);
        amount1 = uint256(-amount1Int);

        if (amount0 > 0 || amount1 > 0) {
            (position.tokensOwed0, position.tokensOwed1) = (
                position.tokensOwed0 + uint128(amount0),
                position.tokensOwed1 + uint128(amount1)
            );
        }
        // NOTE: no transfer of tokens
    }

    struct SwapCache {
        uint128 liquidityStart;
    }

    struct SwapState {
        int256 amountSpecifiedRemaining;
        // amount already swapped out/in of the output/input asset
        int256 amountCalculated;
        uint160 sqrtPriceX96;
        int24 tick;
        // fee growth on input token
        uint256 feeGrowthGlobalX128;
        // current liquidity in range
        uint128 liquidity;
    }

    struct StepComputations {
        uint160 sqrtPriceStartX96;
        int24 tickNext;
        // whether tickNext is initialized or not
        bool initialized;
        uint160 sqrtPriceNextX96;
        // how much is being swapped in in this step
        uint256 amountIn;
        // how much is being swapped out
        uint256 amountOut;
        // how much fee is being paid in
        uint256 feeAmount;
    }

    /// @notice Swap one token for another
    /// @param recipient The address to receive the output tokens
    /// @param zeroForOne Whether to swap token0 for token1 (true) or token1 for token0 (false)
    /// @param amountSpecified The amount to swap (positive = exact input, negative = exact output)
    /// @param sqrtPriceLimitX96 The Q64.96 sqrt price limit
    /// @return amount0 The amount of token0 swapped (negative = out, positive = in)
    /// @return amount1 The amount of token1 swapped (negative = out, positive = in)
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    ) external lock returns (int256 amount0, int256 amount1) {
        require(amountSpecified != 0);

        Slot0 memory slot0Start = slot0;

        // token 1 | token 0
        // --------|---------
        //        tick
        // <-- zero for one
        require(
            zeroForOne
                ? sqrtPriceLimitX96 < slot0Start.sqrtPriceX96
                    && sqrtPriceLimitX96 > TickMath.MIN_SQRT_RATIO
                : sqrtPriceLimitX96 > slot0Start.sqrtPriceX96
                    && sqrtPriceLimitX96 < TickMath.MAX_SQRT_RATIO,
            "invalid sqrt price limit"
        );

        SwapCache memory cache = SwapCache({liquidityStart: liquidity});

        // true = sell some specified amount of token in
        // false = buy some specified amount of token out
        bool exactInput = amountSpecified > 0;

        SwapState memory state = SwapState({
            amountSpecifiedRemaining: amountSpecified,
            amountCalculated: 0,
            sqrtPriceX96: slot0Start.sqrtPriceX96,
            tick: slot0Start.tick,
            // Fee on token in
            feeGrowthGlobalX128: zeroForOne
                ? feeGrowthGlobal0X128
                : feeGrowthGlobal1X128,
            liquidity: cache.liquidityStart
        });

        while (
            state.amountSpecifiedRemaining != 0
                && state.sqrtPriceX96 != sqrtPriceLimitX96
        ) {
            StepComputations memory step;

            step.sqrtPriceStartX96 = state.sqrtPriceX96;

            // Get next tick
            (step.tickNext, step.initialized) = tickBitmap
                .nextInitializedTickWithinOneWord(
                state.tick,
                tickSpacing,
                // zero for one --> price decreases --> lte
                // one for zero --> price increases --> gt
                zeroForOne
            );

            // Bound tick next
            if (step.tickNext < TickMath.MIN_TICK) {
                step.tickNext = TickMath.MIN_TICK;
            } else if (step.tickNext > TickMath.MAX_TICK) {
                step.tickNext = TickMath.MAX_TICK;
            }

            step.sqrtPriceNextX96 = TickMath.getSqrtRatioAtTick(step.tickNext);

            (state.sqrtPriceX96, step.amountIn, step.amountOut, step.feeAmount)
            = SwapMath.computeSwapStep(
                state.sqrtPriceX96,
                // zero for one --> max(next, limit)
                // one for zero --> min(next, limit)
                (
                    zeroForOne
                        ? step.sqrtPriceNextX96 < sqrtPriceLimitX96
                        : step.sqrtPriceNextX96 > sqrtPriceLimitX96
                ) ? sqrtPriceLimitX96 : step.sqrtPriceNextX96,
                state.liquidity,
                state.amountSpecifiedRemaining,
                fee
            );

            if (exactInput) {
                // Decreases to 0
                state.amountSpecifiedRemaining -=
                    (step.amountIn + step.feeAmount).toInt256();
                state.amountCalculated -= step.amountOut.toInt256();
            } else {
                // Increases to 0
                state.amountSpecifiedRemaining += step.amountOut.toInt256();
                state.amountCalculated +=
                    (step.amountIn + step.feeAmount).toInt256();
            }

            if (state.liquidity > 0) {
                // fee growth += fee amount * (1 << 128) / liquidity
                state.feeGrowthGlobalX128 += FullMath.mulDiv(
                    step.feeAmount, FixedPoint128.Q128, state.liquidity
                );
            }

            // shift tick if we reached the next price
            if (state.sqrtPriceX96 == step.sqrtPriceNextX96) {
                if (step.initialized) {
                    int128 liquidityNet = ticks.cross(
                        step.tickNext,
                        zeroForOne
                            ? state.feeGrowthGlobalX128
                            : feeGrowthGlobal0X128,
                        zeroForOne
                            ? feeGrowthGlobal1X128
                            : state.feeGrowthGlobalX128
                    );

                    if (zeroForOne) {
                        liquidityNet = -liquidityNet;
                    }

                    state.liquidity = liquidityNet < 0
                        ? state.liquidity - uint128(-liquidityNet)
                        : state.liquidity + uint128(liquidityNet);
                }
                // zeroForOne = true --> tickNext <= state.tick
                // if tickNext = state.tick --> nextInitializedTick = tickNext, so -1 to get next tick
                // if tickNext < state.tick --> nextInitializedTick = tickNext, so -1 to get next tick
                state.tick = zeroForOne ? step.tickNext - 1 : step.tickNext;
            } else if (state.sqrtPriceX96 != step.sqrtPriceStartX96) {
                // state.sqrtPriceX96 is still in between 2 initialized ticks
                // Recompute tick
                state.tick = TickMath.getTickAtSqrtRatio(state.sqrtPriceX96);
            }
        }

        // Update sqrtPriceX96 and tick
        if (state.tick != slot0Start.tick) {
            (slot0.sqrtPriceX96, slot0.tick) = (state.sqrtPriceX96, state.tick);
        } else {
            slot0.sqrtPriceX96 = state.sqrtPriceX96;
        }

        // Update liquidity
        if (cache.liquidityStart != state.liquidity) {
            liquidity = state.liquidity;
        }

        // Update fee growth
        if (zeroForOne) {
            feeGrowthGlobal0X128 = state.feeGrowthGlobalX128;
        } else {
            feeGrowthGlobal1X128 = state.feeGrowthGlobalX128;
        }

        // Set amount0 and amount1
        // zero for one | exact input |
        //    true      |    true     | amount 0 = specified - remaining (> 0)
        //              |             | amount 1 = calculated            (< 0)
        //    false     |    false    | amount 0 = specified - remaining (< 0)
        //              |             | amount 1 = calculated            (> 0)
        //    false     |    true     | amount 0 = calculated            (< 0)
        //              |             | amount 1 = specified - remaining (> 0)
        //    true      |    false    | amount 0 = calculated            (> 0)
        //              |             | amount 1 = specified - remaining (< 0)
        (amount0, amount1) = zeroForOne == exactInput
            ? (
                amountSpecified - state.amountSpecifiedRemaining,
                state.amountCalculated
            )
            : (
                state.amountCalculated,
                amountSpecified - state.amountSpecifiedRemaining
            );

        // Transfer tokens
        if (zeroForOne) {
            if (amount1 < 0) {
                IERC20(token1).transfer(recipient, uint256(-amount1));
                IERC20(token0).transferFrom(
                    msg.sender, address(this), uint256(amount0)
                );
            }
        } else {
            if (amount0 < 0) {
                IERC20(token0).transfer(recipient, uint256(-amount0));
                IERC20(token1).transferFrom(
                    msg.sender, address(this), uint256(amount1)
                );
            }
        }
    }

    // Test helper functions
    function getSlot0() external view returns (Slot0 memory) {
        return slot0;
    }

    function getPosition(address owner, int24 tickLower, int24 tickUpper)
        external
        view
        returns (Position.Info memory)
    {
        return positions.get(owner, tickLower, tickUpper);
    }
}
