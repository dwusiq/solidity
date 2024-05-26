import { BigNumber, Contract } from "ethers";
import { ethers } from "hardhat";


import { ENV } from "./constants";
import { initContract, parseLayerZeroTestCoin } from "./commonUtils";
import moment from "moment/moment";
const { deploy, waitTrans } = require("./contractDeploy.ts");

//一些默认的参数
export interface DefaultParam {
  env: ENV;
  layerZeroTestCoinDecimal: number;
  deployerAddress: string; //当前部署者钱包地址，可以不填，默认会赋值
  //https://layerzero.gitbook.io/docs/technical-reference/testnet/testnet-addresses
  //https://layerzero.gitbook.io/docs/technical-reference/mainnet/supported-chain-ids
  endpointAddress: string; //根据当前端点合约地址
  destinationLayerZeroTestAddress: string; //跨链目标链的[layerZeroTest.sol]合约地址
  destinationLayerZeroTestCoinAddress: string; //跨链目标链的[LayerZeroTestCoin.sol]合约地址
}

//合约地址
//已部署合约字段名： deployed+XXXX
//合约地址字段名： xxxx+Addr
export interface ContractInfo {
  deployedLayerZeroTest?: Contract;
  layerZeroTestAddr: string; //layerZeroTest合约
  deployedLayerZeroTestCoin?: Contract;
  layerZeroTestCoinAddr: string; //LayerZeroTestCoin合约
}

//已部署的合约信息
let p: DefaultParam;
//已部署的合约信息
let c: any;

/**
 * @notice 初始化或者部署合约信息
 * @param sourceParam 默认参数
 * @param sourceContract 合约信息源
 */
export async function initOrDeployContract(sourceParam: DefaultParam, sourceContract: ContractInfo) {
  let [deployer] = await ethers.getSigners();
  p = sourceParam;
  p.deployerAddress = deployer.address;
  c = sourceContract;

  //部署
  await deployContract();

  //初始化commUtils的合约
  await initContract(p, c);
}

//部署合约
async function deployContract() {
  console.log(`[deployContract] start.`);
  try {
    [c.deployedLayerZeroTest, c.layerZeroTestAddr] = await deploy("LayerZeroTest", c.layerZeroTestAddr, [p.endpointAddress]);
    [c.deployedLayerZeroTestCoin, c.layerZeroTestCoinAddr] = await deploy("LayerZeroTestCoin", c.layerZeroTestCoinAddr, [p.endpointAddress]);
    // [c.deployedPresale, c.presaleAddr] = await upgradeDeploy("PresaleContract", c.presaleAddr, []);
  } catch (ex) {
    console.error("ex", ex);
  } finally {
    //打印合约地址
    printContractInfo();
  }
}

function printContractInfo() {
  // 遍历属性名，只打印指定名字属性对应的值
  Object.keys(c).forEach((propertyName) => {
    if (!propertyName.startsWith("deployed")) {
      let contractName = propertyName.substring(0, propertyName.lastIndexOf("Addr"));
      console.log(`${propertyName}: "${c[propertyName]}",//${contractName}`);
    }
  });
}

//初始化LayerZeroTes合约
export async function initLayerZeroTest() {
  await waitTrans(await c.deployedLayerZeroTest.trustAddress(p.destinationLayerZeroTestAddress), "layzerZero.trustAddress");
}

//发送跨链消息
export async function sendLayerZeroTestMessage() {
  const message = `message on time:${moment().format("YYYY:MM:DD HH:mm:ss")}`;
  const transactionFee = 1234567890000000; //WEI
  await waitTrans(await c.deployedLayerZeroTest.send(message, { value: transactionFee }), `layzerZero.send(${message})`);
}



//初始化LayerZeroTestCoin合约
export async function initLayerZeroTestCoin() {
  await waitTrans(await c.deployedLayerZeroTestCoin.trustAddress(p.destinationLayerZeroTestCoinAddress), "layzerZero.trustAddress");
}

//代币跨链
export async function bridgeLayerZeroTestCoin() {
  const bridgeAmount = Math.floor(Math.random() * 500) + 1;
  const bridgeAmountBn = parseLayerZeroTestCoin(bridgeAmount);
  const transactionFee = 1234567890000000; //WEI
  await waitTrans(await c.deployedLayerZeroTestCoin.bridge(bridgeAmountBn, { value: transactionFee }), `layzerZero.bridge(${bridgeAmount})`);
}

//升级合约
export async function deployedContractUpgrade() {
  // await upgradeContract("PresaleContract", c.presaleAddr);
}

export async function tmpSet() {
  console.log(`data:${(await c.deployedLayerZeroTest.data()).toString()}`);
}
