import { ethers } from "hardhat";


export async function deployContract(contractName: string, params: any, deployer = undefined) {
    const contract = await ethers.deployContract(contractName, params, deployer);
    await contract.waitForDeployment();
    console.log(`deployed ${contractName} ===> ${contract.target}`);
    return contract;
  }
  
  
  
  /**
   * Create signature
   * @param chainId Tx will send to this chain
   * @param token Sending token
   * @param amount Sending amount
   * @param to Send token to this address
   * @param message any string, or empty
   * @param currentNo Increase number each tx
   * @returns 
   */
  export function createPayloadHash(
    chainId: number,
    token: string,
    amount: BigInt,
    to: string,
    message: string,
    currentNo: number
  ) {
    return ethers.solidityPackedKeccak256(["uint256", "address", "uint256", "address", "string", "uint256"], [chainId, token, amount, to, message, currentNo]);
  };