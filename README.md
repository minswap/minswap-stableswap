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

## References

1. [Specification](/stableswap-docs/stableswap-spec.md)
2. [Stableswap Formula](/stableswap-docs/formula.md)
3. [Audit Report](/audit-report/TxPipe-audit-report.pdf)