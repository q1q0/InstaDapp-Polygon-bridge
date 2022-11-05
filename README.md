# Instadapp Lite Polygon

This repository contains the core contracts for Instadapp Lite on Polygon.

## Installation

1. Install NPM Packages

```javascript
npm i
```

2. Create a `.env` file in the root directory and use the below format for .`env` file (see .env.example).

```javascript
ALCHEMY_TOKEN = "<Replace with your Alchemy Key>"; //For deploying
```

## Commands:

Run the local node

```
npx hardhat node
```

Compile contracts

```
npm run compile
```

Run the testcases (run the local node first)

```
npm test
```

Get the test coverage

```
npm run coverage
```

### Run Coverage Report for Tests

`npm run coverage`

Notes:

- running a coverage report currently deletes artifacts, so after each coverage run you will then need to run `npx hardhat clean` followed by `npm run build` before re-running tests
- the branch coverage is 75%

### Deploy to Polygon

Create/modify network config in `hardhat.config.ts` and add API key and private key, then run:

`npx hardhat run --network <HARDHAT_NETWORK> scripts/deploy.ts`

### Verify on Etherscan

Using the [hardhat-etherscan plugin](https://hardhat.org/plugins/nomiclabs-hardhat-etherscan.html), add Etherscan API key to `hardhat.config.ts`, then run:

`npx hardhat verify --network <HARDHAT_NETWORK> <DEPLOYED ADDRESS>`
