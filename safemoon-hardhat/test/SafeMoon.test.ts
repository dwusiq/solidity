const { expect } = require("chai");
const { ethers } = require("hardhat");




describe("SafeMoon Test", function () {
    const decimalUsdt = 18;
    const decimalEth = 18;
    const decimalSafemoon = 9;

    let usdt: any, wbnb: any, uniswapV2Factory: any, uniswapV2Router02: any, safeMoon: any;
    let usdtAddr: any, wbnbAddr: any, uniswapV2FactoryAddr: any, uniswapV2Router02Addr: any, safeMoonAddr: any;
    let deployer: any, user0: any, user1: any, user2: any, user3: any, user4: any;

    //参数初始化
    it("init params", async function () {
        [deployer, user0, user1, user2, user3, user4] = await ethers.getSigners();
    });

    //合约部署
    it("deploy all contract", async function () {
        const ftryUsdt = await ethers.getContractFactory("BEP20USDT");
        usdt = await ftryUsdt.deploy();
        await usdt.deployed();
        usdtAddr = usdt.address;

        const ftryWBNB = await ethers.getContractFactory("WBNB");
        wbnb = await ftryWBNB.deploy();
        await wbnb.deployed();
        wbnbAddr = wbnb.address;

        const ftryUniswapV2Factory = await ethers.getContractFactory("UniswapV2Factory");
        uniswapV2Factory = await ftryUniswapV2Factory.deploy(wbnb.address);
        await uniswapV2Factory.deployed();
        uniswapV2FactoryAddr = uniswapV2Factory.address;

        const ftryUniswapV2Router02 = await ethers.getContractFactory("UniswapV2Router02");
        uniswapV2Router02 = await ftryUniswapV2Router02.deploy(uniswapV2Factory.address, wbnb.address);
        await uniswapV2Router02.deployed();
        uniswapV2Router02Addr = uniswapV2Router02.address;

        const SafeMoon = await ethers.getContractFactory("SafeMoon");
        safeMoon = await SafeMoon.deploy(uniswapV2Router02Addr);
        await safeMoon.deployed();
        safeMoonAddr = safeMoon.address;

        //log
        console.log("deployer:%s", deployer.address);
        console.log("usdtAddr:%s", usdtAddr);
        console.log("wbnbAddr:%s", wbnbAddr);
        console.log("uniswapV2FactoryAddr:%s", uniswapV2FactoryAddr);
        console.log("uniswapV2Router02Addr:%s", uniswapV2Router02Addr);
        console.log("safeMoonAddr:%s", safeMoonAddr);
    });


    //函数调用
    it("function test", async function () {
        //get deployer balance
        let defaultDeployerBalance = await safeMoon.balanceOf(deployer.address);
        console.log('safemoon-deployer-balance', defaultDeployerBalance.toString());
        console.log('safemoon-deployer-bigUnit', ethers.utils.formatUnits(defaultDeployerBalance.toString(), decimalSafemoon));

        //transfer
        const transferAmount = "1000";
        await safeMoon.transfer(user0.address,ethers.utils.parseUnits(transferAmount, decimalUsdt));


        // let defaultDeployerBalance1 = await safeMoon.balanceOf(deployer.address);
        // console.log('safemoon-deployer-balance1', ethers.utils.formatUnits(defaultDeployerBalance1.toString(), decimalSafemoon));

        
        // let user0Balance = await safeMoon.balanceOf(user0.address);
        // console.log('safemoon-user0-balance', ethers.utils.formatUnits(user0Balance.toString(), decimalSafemoon));


        
        await safeMoon.connect(user0).transfer(user1.address,ethers.utils.parseUnits("300", decimalUsdt));
        let defaultDeployerBalance1 = await safeMoon.balanceOf(user0.address);
        console.log('safemoon-user0-balance', ethers.utils.formatUnits(defaultDeployerBalance1.toString(), decimalSafemoon));

        
        let user1Balance = await safeMoon.balanceOf(user1.address);
        console.log('safemoon-user1-balance', ethers.utils.formatUnits(user1Balance.toString(), decimalSafemoon));

        
    });



});