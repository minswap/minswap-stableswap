# Minswap Stableswap Contract

## Structure
- There are 4 mains contract under `validators` folder and utility functions under `lib/stableswap` folder

## Building

- Make sure you have already installed `npm` and `aiken`
- Run `npm install` to install necessary dependencies 
- Run `npx ts-node --esm build-plutus.ts` to build scripts. The result is `stableswap-script.json` file

## Testing

- Run `aiken check` to run all unit tests of the contract

## References

1. [Specification](/stableswap-docs/stableswap-spec.md)
2. [Stableswap Formula](/stableswap-docs/formula.md)
3. [Audit Report](/audit-report/TxPipe-audit-report.pdf)