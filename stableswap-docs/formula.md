# Minswap Stableswap Formula
References: https://miguelmota.com/blog/understanding-stableswap-curve/

Base on the Article above, we finalize Stableswap formula is:
$$A.n^{n}.\sum_{0}^{i}x + D = A.D.n^{n} + \frac{D^{n+1}}{n^{n}.\prod_{0}^{i}x} $$

Before we go to details, we need define some variables:
- n: Number of Tokens
- A: Amplification coefficient factor
- D: Sum variant
- $x$: Pool balance
multiples: the multiple of stable assets, using for calculation between stable assets with different decimals

## Core formula
Almost all Stableswap calculations are using 2 core formulas. 

First is calculating Constant Sum Variant (get D) and calculating balance after exchaging (get Y)
### get D
From the Stableswap formula, we change it to
$$\frac{D^{n+1}}{n^{n}.\prod_{0}^{i}x} + D.(A.n^{n} - 1) - A.n^{n}.\sum_{0}^{i}x = 0$$

$$f(D) = \frac{D^{n+1}}{n^{n}.\prod_{0}^{i}x} + D.(A.n^{n} - 1) - A.n^{n}.\sum_{0}^{i}x$$
$$f'(D) = (n+1).\frac{D^{n}}{n^{n}.\prod_{0}^{i}x} + (A.n^{n} - 1)$$

Base on [Newton method](https://en.wikipedia.org/wiki/Newton%27s_method), we find the approximation root of the formula above:

$$x^{n+1} = x_{n} - \frac{f(x_{n})}{f'(x_{n})}$$

$$D_{n+1} = D_{n} - \frac{f(D_{n})}{f'(D_{n})}$$
$$D_{n+1} = D_{n} - \frac{\frac{D_{n}^{n+1}}{n^{n}.\prod_{0}^{i}x} + D_{n}.(A.n^{n} - 1) - A.n^{n}.\sum_{0}^{i}x}{(n+1).\frac{D^{n}}{n^{n}.\prod_{0}^{i}x} + (A.n^{n} - 1)}$$

$$D_{n+1} = \frac{D_{n} * ((n+1).\frac{D^{n}}{n^{n}.\prod_{0}^{i}x} + (A.n^{n} - 1)) - \frac{D_{n}^{n+1}}{n^{n}.\prod_{0}^{i}x} + D_{n}.(A.n^{n} - 1) - A.n^{n}.\sum_{0}^{i}x}{(n+1).\frac{D^{n}}{n^{n}.\prod_{0}^{i}x} + (A.n^{n} - 1)}$$ 

Let $DP = \frac{D_{n}^{n+1}}{n^{n} . \prod_{0}^{i}x}$ and we multiple $D_{n}$ on both numerator and denominator of right side, we have:

$$D_{n+1} = \frac{(n . DP + A.n^{n}.\sum_{0}^{i}x).D_{n}}{(n + 1).DP + (A.n^{n} - 1).D_{n}}$$


### get Y

Let say, after exchanging, the new balance sum and new balance prod is: 
$\sum_{0}^{i}x'$ and $\prod_{0}^{i}x'$

$$A.n^{n}.\sum_{0}^{i}x' + D = A.D.n^{n} + \frac{D^{n+1}}{n^{n}.\prod_{0}^{i}x'}$$
Equal to
$$A.n^{n}.(\sum_{0}^{i}x' - y + y) + D = A.D.n^{n} + \frac{D^{n+1}}{n^{n}.\frac{\prod_{0}^{i}x'}{y}.y}$$
Equal to
$$A.n^{n}.y^{2} + y . (A.n^{n}.(\sum_{0}^{i}x' - y) + D - A.n^{n}.D) - \frac{D^{n+1}}{n^{n}.\frac{\prod_{0}^{i}x'}{y}} = 0$$
Equal to
$$y^{2} + y . ((\sum_{0}^{i}x' - y) + \frac{D}{A.n^{n}} - D) - \frac{D^{n+1}}{A.n^{n}.n^{n}.\frac{\prod_{0}^{i}x'}{y}} = 0$$

Use [Newton method](https://en.wikipedia.org/wiki/Newton%27s_method), we have
$$f(y) = y^{2} + y . ((\sum_{0}^{i}x' - y) + \frac{D}{A.n^{n}} - D) - \frac{D^{n+1}}{A.n^{n}.n^{n}.\frac{\prod_{0}^{i}x'}{y}}$$
$$f'(y) = 2.y + ((\sum_{0}^{i}x' - y) + \frac{D}{A.n^{n}} - D)$$
Then
$$y_{i} = \frac{y_{i-1}^{2} + \frac{D^{n+1}}{A.n^{n}.n^{n}.\frac{\prod_{0}^{i}x'}{y_{i-1}}}}{2.y_{i-1} + ((\sum_{0}^{i}x' - y_{i-1}) + \frac{D}{A.n^{n}} - D)}$$


## Use case formula

On our Stableswap, we do not use Token Balance for calculation because Stableswap Tokens can have different decimals. So:
- Calculation Balance: Token Balance * Multiple
- $A.n^{n}$: A variable on Pool Datum

You can checkout the code to see more about each use case formula:
- Deposit: `calculate_deposit`
- Exchange: `calculate_exchange`
- Withdraw: `calculate_withdraw`
- Withdraw Imbalance: `validate_withdraw_imbalance`
- Withdraw One Coin: `calculate_withdraw_one_coin`
