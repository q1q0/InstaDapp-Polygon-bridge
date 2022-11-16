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

### Deploy

There is a hardhat task that will:

- deploy the LiteVault
- deploy the LiteVaultProxy

Usage:

- Set the `ALCHEMY_TOKEN_<NETWORK>` for the network you want to deploy to in `.env`, see .env.example
- Add either the private key or mnemonic for the deployer address in `.env`
- Run:
  `npx hardhat deploy-vault <PROXY_ADMIN_ADDRESS> --network <HARDHAT_NETWORK>`

`PROXY_ADMIN_ADDRESS` is the admin for the LiteVaultProxy.

### Verify on Etherscan

Using the [hardhat-etherscan plugin](https://hardhat.org/plugins/nomiclabs-hardhat-etherscan.html), add Etherscan API key to `hardhat.config.ts`, then run:

`npx hardhat verify --network <HARDHAT_NETWORK> <DEPLOYED ADDRESS>`
