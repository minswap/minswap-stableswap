# 😻 Minswap Stableswap Contract

## Structure
- Main contracts:
  - Order & Order Batching Validators `/validator/order_validator.ak`
  - Pool Validator `/validator/pool_validator.ak`
  - LP Minting Policy `/validator/lp_minting_policy.ak`
- Library: under `/lib/stableswap` package

## Building

### Prerequisites
- Install npm: https://docs.npmjs.com/downloading-and-installing-node-js-and-npm
- Install Aiken v1.0.21-alpha: https://aiken-lang.org/installation-instructions
- Run `aiken build` to double check scripts bytecode in `plutus.json` file 
- Run `npm install` to install necessary dependencies 
- Run `npx ts-node --esm build-plutus.ts` to build scripts with initial parameters. The result is `stableswap-script.json` file

## Testing

- Run `aiken check` to run all unit tests of the contract
- Minswap Testnet Preprod website: https://testnet-preprod.minswap.org/

## Setup Stableswap Liquidity Pool
Minswap Stableswap Contracts depends on contract's parameters: 

1. Pool NFT: must be minted by Time-Lock script and its quantity must be 1
2. Assets: the stable assets which the Pool supports trading
3. Multiples: is the multiple of stable assets, using for calculation between stable assets with different decimals.
4. Fee: the numerator of the fee % users need to pay when interacting with the pool
5. Admin Fee: the numerator of the % of the fee that goes to Admin
6. Fee Denominator: is the denominator of fee and admin_fee, which help calculation more accurate
7. License Curreny Symbol: used for minting Batcher License assets. 
8. Admin Asset: is used to identify Admin
9. Maximum Deadline Range: is the maximum expiration time of Batcher license from now

When these parameters are prepared, the Smart Contract can be built by using `buiid-plutus.ts` script. 

## Smart Contract Limitation

### 1. Batcher
In the Stableswap system, an entity known as the "Batcher" plays a crucial role in processing User Requests (Orders). Batchers are centralized agents, authorized by the Protocol Owner through a Batcher License Asset.

### 2. Pool NFT
The Pool NFT is a key component in Stableswap, uniquely identifying each Pool and playing a pivotal role. It is responsible for authorizing LP Token Minting. However, if the Pool NFT and the Pool are not configured correctly, it could potentially compromise the LP Minting Policy Contract.

- *Legitimate Initialization*:

  - Mint a single Pool NFT using a Time-Lock Script.
  - Utilize the Pool NFT to establish a Stable Pool.

- *Malicious Initialization*:
  - Failure to mint the Pool NFT via Time-Lock Script, or minting more than one Asset.
  - Misuse of the Pool NFT to mint LP Tokens prior to the creation of the Stable Pool.

**To ensure security and uniqueness, users intending to interact with Stable Pools outside of the Minswap interface must verify that the Pool NFT has been minted correctly. This verification is crucial to ensure that the Pool NFT is unique and cannot be replicated or minted again.**
## References

1. [Specification](/stableswap-docs/stableswap-spec.md)
2. [Stableswap Formula](/stableswap-docs/formula.md)
3. [Audit Report](/audit-report/TxPipe-audit-report.pdf)

## Deployed contract

- [DJED-iUSD Pool](./deployed-contract/djed-iusd/deployed.md)
- [USDC-DJED Pool](./deployed-contract/usdc-djed/deployed.md)
- [USDM-iUSD Pool](./deployed-contract/usdm-iusd/deployed.md)