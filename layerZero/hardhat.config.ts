import "@nomiclabs/hardhat-web3";
import "@openzeppelin/hardhat-upgrades";
import "hardhat-deploy";
import "hardhat-deploy-ethers";
import "hardhat-gas-reporter";
require("@nomiclabs/hardhat-etherscan");
import { HardhatUserConfig } from "hardhat/types";
require("dotenv").config();
const { TES_GOERLI_KEY, TES_ARBITRUM_GOERLI_KEY } = process.env;

const config: HardhatUserConfig = {
  networks: {
    hardhat: {
      allowUnlimitedContractSize: false,
    },
    testnetGoerli: {
      url: "https://rpc.ankr.com/eth_goerli",
      chainId: 5,
      // gasPrice: 20000000000,
      accounts: [`${TES_GOERLI_KEY}`], //第一个owner,
      timeout: 60000, //这里时间给长一点，不然容易超时
    },
    testnetArbitrumGoerli: {
      url: "https://arbitrum-goerli.publicnode.com",
      chainId: 421613,
      accounts: [`${TES_ARBITRUM_GOERLI_KEY}`], //第一个owner,
      timeout: 60000, //这里时间给长一点，不然容易超时
    },
  },

  solidity: {
    compilers: [
      {
        version: "0.8.17",
      },
    ],
    // overrides: {
    //   "contracts/IDO/PresaleContract.sol": {
    //     version: "0.8.2",
    //     settings: {
    //       //如果合约内容过大，导致部署失败，可以尝试用该配置优化一下合约
    //       optimizer: {
    //         enabled: true,
    //         runs: 1000,
    //       },
    //     },
    //   }
    // },
  },
};

export default config;
