x = token 0
y = token 1
p = price of x in terms of y = y/x
p = 1.0001^tick * decimals0/decimals1

# Tick and Price Explanation
Each tick represents a 0.01% (1.0001x) price increase from the previous tick. 
For example:
- Tick 0: Base price (adjusted for token decimals)
- Tick 1: Price is 1.0001x higher than tick 0
- Tick 100: Price is (1.0001)^100 higher than tick 0

tick spacing = number of ticks to skip when the price moves
- Lower tick spacing (e.g., 1): More granular prices, higher gas costs
- Higher tick spacing (e.g., 60): Less granular prices, lower gas costs

Example: In a USDC/ETH pool
- At tick 0: price = 1.0001^0 * (10^6/10^18) = 10^-12
- At tick 202719: price ≈ 2000 USDC per ETH

## sqrtPriceX96
X = token 0
Y = token 1
p = price of X in terms of Y = Y/X
p = (sqrtPriceX96 / 2^96)^2 * (decimalsX / decimalsY)
sqrtPriceX96 = sqrt(p) * 2^96
