//npx hardhat run scripts/deploy-sepolia-test.ts --network testnetSepolia
import { deployContract } from "../utils/deployUtils";
const { ethers } = require("hardhat");

//!!!!!!!!!!!!!! Careful  need: change
let signerList = ["0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", "0x70997970C51812dc3A010C7d01b50e0d17dc79C8", "0x90F79bf6EB2c4f870365E785982E1f101E93b906"];//!!!!!!!!!!!!!!!!!!!!!!All address of signers


let deployer: any, deployerAddress: string;
let deployedUsdt: any,
  usdtAddress: string,
  deployedWallet: any,
  multiSignAddress: string;


//deploy
async function deployContracts() {
  //deploy usdt
  deployedUsdt = await deployContract("UsdToken", [], deployer);
  usdtAddress = deployedUsdt.target;

  //deploy multiSignWallet
  const signNumMin = signerList.length * 2 / 3;
  deployedWallet = await deployContract("MultiSignWallet", [signerList, signNumMin], deployer);
  multiSignAddress = deployedWallet.target;
};





async function main() {
  [deployer] = await ethers.getSigners();
  deployerAddress = deployer.address;
  console.log(">>>>deployer:", deployer.address);

  //deploy
  await deployContracts();
}

main()
  .then(() => process.exit())
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

export { };
