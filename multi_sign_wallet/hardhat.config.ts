import type { HardhatUserConfig } from "hardhat/config";
import "hardhat-deploy";
import "hardhat-deploy-ethers";
import "hardhat-gas-reporter";
import "@nomicfoundation/hardhat-viem";
require("@nomicfoundation/hardhat-toolbox");
const { OWNER_KEY, TEST_EVM_OWNER_KEY } = require("./env.json");


const config: HardhatUserConfig = {
  solidity: "0.8.24",

  networks: {
    testnetSepolia: {
      url: "https://sepolia.drpc.org",
      chainId: 11155111,
      accounts: [`${TEST_EVM_OWNER_KEY}`],
    },
  }
};

export default config;