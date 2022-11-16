import { config as dotEnvConfig } from "dotenv";
dotEnvConfig();

import { HardhatUserConfig } from "hardhat/types";

import "@nomiclabs/hardhat-waffle";
import "@typechain/hardhat";
import "@nomiclabs/hardhat-etherscan";
import "solidity-coverage";

interface Etherscan {
  etherscan: { apiKey: string | undefined };
}

type HardhatUserEtherscanConfig = HardhatUserConfig & Etherscan;

const ALCHEMY_TOKEN = process.env.ALCHEMY_TOKEN || "";
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY;

const config: HardhatUserEtherscanConfig = {
  defaultNetwork: "hardhat",
  solidity: {
    compilers: [{ version: "0.8.17", settings: {} }],
  },
  networks: {
    hardhat: {
      forking: {
        url: "https://polygon-mainnet.g.alchemy.com/v2/" + ALCHEMY_TOKEN,
        blockNumber: 35364715,
      },
      gasPrice: 4985670377180,
      gas: 6000000,
    },
    localhost: {},
    coverage: {
      url: "http://127.0.0.1:8555", // Coverage launches its own ganache-cli client
    },
  },
  etherscan: {
    // Your API key for Etherscan
    // Obtain one at https://etherscan.io/
    apiKey: ETHERSCAN_API_KEY,
  },
};

export default config;
