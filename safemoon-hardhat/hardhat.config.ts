import 'hardhat-deploy';
import 'hardhat-deploy-ethers';
import { HardhatUserConfig } from 'hardhat/types';

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: '0.6.12', // 支持solidity版本
      }],
    overrides: {
      "contracts/uniswapForTest/BEP20USDT.sol": {
        version: "0.5.16",
        settings: {
        }
      },
      "contracts/uniswapForTest/WBNB.sol": {
        version: "0.4.18",
        settings: {
        }
      },
      "contracts/uniswapForTest/UniswapV2Factory.sol": {
        version: "0.5.16",
        settings: {
          evmVersion: "istanbul",
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      },
      "contracts/uniswapForTest/UniswapV2Router02.sol": {
        version: "0.6.6",
        settings: {
          evmVersion: "istanbul",
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      }
    }
  },
  // namedAccounts: {
  //   deployer: 0,
  // },
};
export default config;