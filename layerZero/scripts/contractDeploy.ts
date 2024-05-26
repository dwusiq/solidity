import { ethers, upgrades } from "hardhat";
import { FactoryOptions } from "hardhat/types";
let moment = require("moment");

let isLocalTest = false; //是否是本地测试， true: 本地测试  false: 部署远程节点    如果本地测试则部署之后不会进行睡眠
async function openLocalTest() {
  isLocalTest = true;
}

//睡眠指定时间
function sleep(ms: any) {
  console.log(moment().format("YYYYMMDD HH:mm:ss"), "DEBUG", "sleep ms " + ms);
  if (!isLocalTest) {
    return new Promise((resolve) => {
      setTimeout(resolve, ms);
    });
  }
}

//等待交易执行完之后，仍继续等待5秒
async function waitTrans(trans: any, transDesc: any) {
  console.log("%s start", transDesc);
  await trans.wait();
  await sleep(6000);
  console.log("%s success", transDesc);
}

/**
 * @notice  合约部署基础函数
 * @param isUpgrade 是不是可升级合约 true-可升级合约 false-不可升级合约
 * @param contractName 合约名称
 * @param selfAddress 合约自己的地址 为空时部署新的，否则只是将合约关联到该地址
 * @param params 合约部署的入参
 */
async function baseDeploy(isUpgrade: boolean, contractName: string, selfAddress: string, params: any[], options?: FactoryOptions) {
  const Contract = await ethers.getContractFactory(contractName, options);
  let deployedContract: any;
  if (!selfAddress || selfAddress == "") {
    console.log(`deploy ${contractName} start`);
    if (isUpgrade) {
      deployedContract = await upgrades.deployProxy(Contract, params, {
        initializer: "initialize",
      });
    } else {
      deployedContract = await Contract.deploy(...params);
    }

    await deployedContract.deployed();
    selfAddress = deployedContract.address;
    console.log(`${contractName} deploy finish, address: ${selfAddress}`);
    await sleep(6000);
  } else {
    deployedContract = Contract.attach(selfAddress);
    console.log(`init ${contractName} success. address: ${selfAddress}`);
  }
  return [deployedContract, selfAddress];
}

//默认的部署
async function deploy(contractName: string, selfAddress: string, params: any[], options?: FactoryOptions) {
  return baseDeploy(false, contractName, selfAddress, params, options);
}

//可升级的部署
async function upgradeDeploy(contractName: string, selfAddress: string, params: any[], options?: FactoryOptions) {
  return baseDeploy(true, contractName, selfAddress, params, options);
}

/**
 * @notice 升级已部署的合约合约
 * @param selfAddress 自己的地址
 */
async function upgradeContract(contractName: string, selfAddress: string) {
  console.log(`${contractName} upgrade start`);

  const Contract = await ethers.getContractFactory(contractName);
  const upgraded = await upgrades.upgradeProxy(selfAddress, Contract);
  console.log(`${contractName} upgrade finish, address:${selfAddress}`);
  return upgraded;
}

export { deploy, waitTrans, sleep, upgradeDeploy, upgradeContract,openLocalTest };
