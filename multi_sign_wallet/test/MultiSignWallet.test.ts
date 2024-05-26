const { ethers } = require("hardhat");
import { expect } from "chai";
import { createPayloadHash, deployContract } from "../utils/deployUtils";



type SendTokenParam = {
  sendToken: string;  //Address of sending token.    usdt:usdtAddress eth:AddressZero
  sendAmt: BigInt; //Amount of sending token
  to: string;  //Send token to this address. but not support AddressZero
  msg: string; //Any string, can be empty
}
let paramSendUSDT: SendTokenParam;
let paramSendETH: SendTokenParam;

let usdtDecimal = 6;
const AddressZero = "0x0000000000000000000000000000000000000000";


describe(">>>> MultiSignWallet test", function () {
  const provider = ethers.provider;
  let owner: any, alice: any, bob: any, tom: any, jon, davi: any, receiver: any;
  let deployedUsdt: any, usdtAddress: string, deployedWallet: any, multiSignAddress: string;

  before(async function () {
    //user list
    [owner, alice, bob, tom, jon, davi, receiver] = await ethers.getSigners();
    console.log(`owner:${owner.address}\r\nalice:${alice.address}\r\ntom:${tom.address}\r\njon:${jon.address}\r\nreceiver${receiver.address}\r\n`);

    //deploy usdt
    deployedUsdt = await deployContract("UsdToken", [], owner);
    usdtAddress = deployedUsdt.target;

    //deploy multiSignWallet
    const allSigner = [alice.address, bob.address, tom.address];
    const signNumMin = allSigner.length * 2 / 3;
    deployedWallet = await deployContract("MultiSignWallet", [allSigner, signNumMin], owner);
    multiSignAddress = deployedWallet.target;

    //Init tokens balance of MultiSignWallet 
    await owner.sendTransaction({ to: multiSignAddress, value: ethers.parseEther("50") });
    await deployedUsdt.mint(multiSignAddress, ethers.parseUnits("10000", usdtDecimal));
    console.log(`Contract hold usdt:${(await deployedUsdt.balanceOf(multiSignAddress)).toString()}`);
    console.log(`Contract hold eth:${(await provider.getBalance(multiSignAddress)).toString()}`);

    //Init param of send token
    paramSendUSDT = {
      sendToken: usdtAddress,
      sendAmt: ethers.parseUnits("10", usdtDecimal),
      to: receiver.address,
      msg: "Send usdt to other",
    }
    paramSendETH = {
      sendToken: AddressZero,
      sendAmt: ethers.parseEther("10"),
      to: receiver.address,
      msg: "Try to send eth",
    }
  });


  it("expect sendUsdt success", async function () {
    // param
    let { sendToken, sendAmt, to, msg } = paramSendUSDT;
    let payloadHash = await deployedWallet.getMessageHash(sendToken, sendAmt, to, msg);

    //sign
    const aliceSignature = await alice.signMessage(ethers.getBytes(payloadHash));
    const bobSignature = await bob.signMessage(ethers.getBytes(payloadHash));

    //send
    const signatures = [aliceSignature, bobSignature];
    await deployedWallet.sendToken(sendToken, sendAmt, to, msg, signatures);

    //check balance
    const sentAmount = await deployedUsdt.balanceOf(to);
    expect(sentAmount.toString()).to.equal(sendAmt.toString());
  });

  it("expect sendETH success", async function () {
    // param
    let { sendToken, sendAmt, to, msg } = paramSendETH;
    let payloadHash = await deployedWallet.getMessageHash(sendToken, sendAmt, to, msg);

    //sign
    const aliceSignature = await alice.signMessage(ethers.getBytes(payloadHash));
    const bobSignature = await bob.signMessage(ethers.getBytes(payloadHash));

    //send
    const balanceBeforeSend = await provider.getBalance(to);
    const signatures = [aliceSignature, bobSignature];
    await deployedWallet.sendToken(sendToken, sendAmt, to, msg, signatures);

    //check balance
    const balanceAfterSent = await provider.getBalance(to);
    expect(balanceAfterSent.toString()).to.equal((balanceBeforeSend + sendAmt).toString());

    //Signature cannot be reused(currentNo is increase)
    await expect(deployedWallet.sendToken(sendToken, sendAmt, to, msg, signatures)).to.be.rejectedWith("Invalid signature");

  });


  it("expect fail: signer not match", async function () {
    // param
    let { sendToken, sendAmt, to, msg } = paramSendETH;
    let payloadHash = await deployedWallet.getMessageHash(sendToken, sendAmt, to, msg);

    //sign
    const bobSignature = await bob.signMessage(ethers.getBytes(payloadHash));
    const daviSignature = await davi.signMessage(ethers.getBytes(payloadHash));

    const signatures = [bobSignature, bobSignature];

    //Twice signature once signer
    await expect(deployedWallet.sendToken(sendToken, sendAmt, to, msg, signatures)).to.be.rejectedWith("Duplicate signer");
    //Sender is not signer
    await expect(deployedWallet.sendToken(sendToken, sendAmt, to, msg, [bobSignature, daviSignature])).to.be.rejectedWith("Invalid signature");
  });


  it("expect fail: sending param not match with signature", async function () {
    // param
    let { sendToken, sendAmt, to, msg } = paramSendETH;
    let payloadHash = await deployedWallet.getMessageHash(sendToken, sendAmt, to, msg);


    //sign
    const aliceSignature = await alice.signMessage(ethers.getBytes(payloadHash));
    const bobSignature = await bob.signMessage(ethers.getBytes(payloadHash));

    const signatures = [aliceSignature, bobSignature];

    //Amount not match 
    await expect(deployedWallet.sendToken(sendToken, BigInt(String(sendAmt)) + BigInt(5), to, msg, signatures)).to.be.rejectedWith("Invalid signature");
    //Receiver not match 
    await expect(deployedWallet.sendToken(sendToken, sendAmt, owner.address, msg, signatures)).to.be.rejectedWith("Invalid signature");
    //Token not match 
    await expect(deployedWallet.sendToken(usdtAddress, sendAmt, to, msg, signatures)).to.be.rejectedWith("Invalid signature");
    //Msg not match 
    await expect(deployedWallet.sendToken(sendToken, sendAmt, to, msg + "hi", signatures)).to.be.rejectedWith("Invalid signature");
    //Signatures not enough
    await expect(deployedWallet.sendToken(sendToken, sendAmt, to, msg, [aliceSignature])).to.be.rejectedWith("Signatures is not enough");
    //Amount is zero
    await expect(deployedWallet.sendToken(sendToken, 0, to, msg, signatures)).to.be.rejectedWith("Amount too low");

  });

  it("expect sendUsdt success:create payload outChain", async function () {
    // param
    let { sendToken, sendAmt, to, msg } = paramSendUSDT;
    const chainId = await deployedWallet.chainId();
    const currentNo = await deployedWallet.currentNo();
    console.log(`chainId:${chainId}\r\ncurrentNo:${currentNo}`);
    let payloadHash = createPayloadHash(chainId, sendToken, sendAmt, to, msg, currentNo)

    //sign
    const aliceSignature = await alice.signMessage(ethers.getBytes(payloadHash));
    const tomSignature = await tom.signMessage(ethers.getBytes(payloadHash));

    //send
    const balanceBeforeSend = await deployedUsdt.balanceOf(to);
    const signatures = [aliceSignature, tomSignature];
    await deployedWallet.sendToken(sendToken, sendAmt, to, msg, signatures);

    //check balance
    const balanceAfterSent = await deployedUsdt.balanceOf(to);
    expect(balanceAfterSent.toString()).to.equal((balanceBeforeSend + sendAmt).toString());

    //expect fail: reSend tx
    await expect(deployedWallet.sendToken(sendToken, sendAmt, to, msg, signatures)).to.be.rejectedWith("Invalid signature");
  });

});


