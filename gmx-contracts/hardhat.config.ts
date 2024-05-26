import "@nomiclabs/hardhat-web3";
import "@openzeppelin/hardhat-upgrades";
import "hardhat-deploy";
import "hardhat-deploy-ethers";
import "hardhat-gas-reporter";
import { HardhatUserConfig } from "hardhat/types";
require("dotenv").config();
const { TEST_OWNER_KEY } = process.env;

const config: HardhatUserConfig = {
  networks: {
    hardhat: {
      allowUnlimitedContractSize: false,
    },
    //polygon测试链
    testnetMumbai: {
      url: "https://rpc.ankr.com/polygon_mumbai",
      chainId: 80001,
      // gasPrice: 20000000000,
      accounts: [`${TEST_OWNER_KEY}`], //第一个owner,
      // timeout: 60000, //这里时间给长一点，不然容易超时
    },
  },
  solidity: {
    compilers: [
      {
        version: "0.6.12",
        settings: {
          optimizer: {
            enabled: true,
            runs: 10,
          },
        },
      },
      {
        version: "0.8.0",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
};
export default config;
