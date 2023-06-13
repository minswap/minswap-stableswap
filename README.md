# Minswap Stableswap Contract

## Structure
- There are 3 mains contract under `validators` folder and utility functions under `lib/stableswap` folder

## Building

- Make sure you have already installed `npm` and `aiken`
- Run `npm install` to install necessary dependencies 
- Run `npx ts-node --esm build-plutus.ts` to build scripts. The result is `stableswap-script.json` file

## Testing

- Run `aiken check` to run all unit tests of the contract

