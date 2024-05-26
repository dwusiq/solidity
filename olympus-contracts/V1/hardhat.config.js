require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-web3");
require("@openzeppelin/hardhat-upgrades");
require("hardhat-deploy");
require("hardhat-deploy-ethers");
require("hardhat-gas-reporter");
// import { HardhatUserConfig } from 'hardhat/types");

const BSC_OWNER_KEY = '03CDf578239E9B91b89D1e0ca7CDD827E5676E43927cEA2e1996363e16F6586c';//BSC主网的OWNER私钥（生产需按实际填写）
const KOVAN_OWNER_KEY = '5511a7aeb49a387168e4cc16a815f7b641d5fa4afe442a2dede56398df6fd84d';//Kovan网的OWNER私钥


const config = {
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true, //不限制合约大小
    },
    kovan: {
      url: `https://kovan.infura.io/v3/0bf59832a3d74ade9625a218acdbecb3`,
      gasPrice: 20000000000,
      accounts: [`0x${KOVAN_OWNER_KEY}`],
      timeout: 40000
    },
    //BSC主链
    mainnetBsc: {
      url: "https://bsc-dataseed.binance.org/",
      chainId: 56,
      gasPrice: 20000000000,
      accounts: [`0x${BSC_OWNER_KEY}`],
    }
  },
  solidity: {
    compilers: [
      {
        version: "0.7.5"
      }],
  },
  namedAccounts: {
    deployer: 0,
    tokenOwner: 1,
    user0: 2,
    user1: 3
  }
};

module.exports = config

// module.exports = {
//   solidity: "0.7.5",
// };
