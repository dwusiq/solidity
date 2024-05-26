import { Contract } from "ethers";
import { ethers, upgrades } from "hardhat";

import { A_DAY_SECONDS, A_HOUR_SECONDS, ENV } from "./constants";
import { ContractInfo, DefaultParam } from "./contract-method-invoke";

//已部署的合约信息
let p: DefaultParam;
//已部署的合约信息
let c: ContractInfo;

/**
 * @notice 初始化或者部署合约信息
 * @param sourceParam 默认参数
 * @param sourceContract 合约信息源
 */
export async function initContract(sourceParam: DefaultParam, sourceContract: ContractInfo) {
  let [deployer] = await ethers.getSigners();
  p = sourceParam;
  p.deployerAddress = deployer.address;
  c = sourceContract;
}

// export function parseEther(value: number | string) {
//   return ethers.utils.parseUnits(String(value), p.ethDecimal);
// }

export function parseLayerZeroTestCoin(value: number | string) {
  return ethers.utils.parseUnits(String(value), p.layerZeroTestCoinDecimal);
}

export function multiDayTimes(days: number) {
  return A_DAY_SECONDS * days;
}

export function multiHourTimes(days: number) {
  return A_HOUR_SECONDS * days;
}
