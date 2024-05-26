// @dev. This script will deploy this V1.1 of Olympus. It will deploy the whole ecosystem except for the LP tokens and their bonds. 
// This should be enough of a test environment to learn about and test implementations with the Olympus as of V1.1.
// Not that the every instance of the Treasury's function 'valueOf' has been changed to 'valueOfToken'... 
// This solidity function was conflicting w js object property name





//执行：npx hardhat run scripts/deployAll.js --network kovan

let moment = require('moment');
const { ethers } = require("hardhat");

let deployerAddress, mockDaoAddress;
let ohmAddress = "0xEebDAd1513eA37399d47bCE63cc25739B7e5a243";
let daiAddress = "0x5c086A8a5E7bcB2309843934bc399800d91817A5";
// let fraxAddress = "0x0B1C5B7DdFE6AEDc5AB6E559D12aE24292299e08";
let sohmAddress = "0xa27D5AB633190f60A16C7EA43C73D87b7F9992C3";
let stakingAddress = "0x0aE953379f04722364Cf51a373CFeB0B73ddd8B9";
let stakingHelperAddress = "0x54CD241BADA492F7c87A2633AbdAfe919Dd2dBaB";
let stakingWarmupAddress = "0x2555360Dc8E71eBD0b0Bc00C2b0b96e5f69a8bF0";
let olympusBondingCalculatorAddress = "0x38aaa0EB5B7eb624cf875FB126387FE33F75A8E9";
let treasuryAddress = "0x0bFb97917f066bA3522E1B15dA5Bd565169093c9";
let distributorAddress = "0xC3bcB2f8c7c253BF2B0a4E838FE0fBe995c76137";
let daiBondAddress = "0x4741aAA1f60E422B100dfc6370EB45A67826Afd5";
let fraxBondAddress = "0x38B6D5A49E67A31028aD43EcF52b294071Fe480a";
let deployedOHM, deployedDai, deployedFrax, deployedSohm, deployedStaking;
let deployedStakingHelper, deployedStakingWarmpup, deployedOlympusBondingCalculator;
let deployedTreasury, deployedDistributor, deployedDaiBond, deployedFraxBond;
let deployer;

//----------------------------
//需要根据实际情况变化的初始变量
//----------------------------
//每个周期(Epoch)包含多少个区块【 How many blocks are in each epoch】
const epochLengthInBlocks = '2200';
// 首个周期(Epoch)的起始区块，如果为空则取当前区块【What epoch will be first epoch】
let firstEpochNumber = '';
//首个周期(Epoch)的结束区块,如果为空，则默认开始块+每个周期（epoch）的区块数（首个结束区块不受epochLengthInBlocks影响）
let firstEpochBlock = '';
// DAI购买债券的BCV【DAI bond BCV】
const daiBondBCV = '369';
// Frax购买债券的BCV【Frax bond BCV】
const fraxBondBCV = '690';
// 用户购买债券的锁仓时长---这是以太坊的时长，其它的需要按实际设置【Bond vesting length in blocks. 33110 ~ 5 days】
const bondVestingLength = '33110';
// 债券最低价【Min bond price】
const minBondPrice = '50000';
// 债券每笔交易的最大支出【Max bond payout】
const maxBondPayout = '50'
// 债券交易中dao手续费【DAO fee for bond(500 = 5% = 0.05 for every 1 paid)】
const bondFee = '10000';
// 最多能被持有多少债券【Max debt bond can take on】
const maxBondDebt = '1000000000000000';
// 初始债券数【Initial Bond debt】
const intialBondDebt = '0'


//常量

// Initial staking index
const initialIndex = '7675210820';
// 初始收益比例【Initial reward rate for epoch】
const initialRewardRate = '3000';
// Ethereum 0 address, used when toggling changes in treasury
const zeroAddress = '0x0000000000000000000000000000000000000000';
// 支持最大的approve[Large number for approval for Frax and DAI]
const largeApproval = '100000000000000000000000000000000';
// 初始mint多少token【Initial mint for Frax and DAI (10,000,000)】
const initialMint = '10000000000000000000000000';



//打印参数 
async function defaultAndPrintParam() {
    //默认，首个周期（epoch）起始区块从当前块开始
    if (!firstEpochNumber || firstEpochNumber == "")
        firstEpochNumber = await ethers.provider.getBlockNumber();
    //默认，首个周期（epoch）结束区块=起始区块+每个周期（epoch）的区块数
    if (!firstEpochBlock || firstEpochBlock == "")
        firstEpochBlock = firstEpochNumber + parseInt(epochLengthInBlocks);
    if (!mockDaoAddress || mockDaoAddress == "")
        mockDaoAddress = deployerAddress;


    console.log("firstEpochNumber: %s", firstEpochNumber);
    console.log("epochLengthInBlocks: %s", epochLengthInBlocks);
    console.log("firstEpochBlock: %s", firstEpochBlock);
    console.log("daiBondBCV: %s", daiBondBCV);
    console.log("fraxBondBCV: %s", fraxBondBCV);
    console.log("bondVestingLength: %s", bondVestingLength);
    console.log("minBondPrice: %s", minBondPrice);
    console.log("maxBondPayout: %s", maxBondPayout);
    console.log("bondFee: %s", bondFee);
    console.log("maxBondDebt: %s", maxBondDebt);
    console.log("intialBondDebt: %s", intialBondDebt);
    console.log("deployerAddress: %s", deployerAddress);
    console.log("mockDaoAddress: %s", mockDaoAddress);
    console.log("initialIndex: %s", initialIndex);
    console.log("initialRewardRate: %s", initialRewardRate);
    console.log("zeroAddress: %s", zeroAddress);
    console.log("largeApproval: %s", largeApproval);
    console.log("initialMint: %s", initialMint);
}
//部署ohm
async function deployOHM() {
    const OHM = await ethers.getContractFactory('OlympusERC20Token');
    if (!ohmAddress || ohmAddress == "") {
        console.log("deploy ohm start");
        deployedOHM = await OHM.deploy();
        ohmAddress = deployedOHM.address;
        await sleep(5000);
    } else {
        console.log("init ohm by address: %s", ohmAddress);
        deployedOHM = OHM.attach(ohmAddress).connect(deployer);
    }
    console.log("ohm finish, ohmAddress: %s", ohmAddress);
}

//部署DAI
async function deployDAI() {
    const DAI = await ethers.getContractFactory('DAI');
    if (!daiAddress || daiAddress == "") {
        console.log("deploy DAI start");
        deployedDai = await DAI.deploy(0);
        daiAddress = deployedDai.address;
        await sleep(5000);
    } else {
        console.log("init DAI by address: %s", daiAddress);
        deployedDai = DAI.attach(daiAddress).connect(deployer);
    }
    console.log("DAI finish,daiAddress: %s", daiAddress);
}

//部署Frax
async function deployFrax() {
    const Frax = await ethers.getContractFactory('FRAX');
    if (!fraxAddress || fraxAddress == "") {
        console.log("deploy Frax start");
        deployedFrax = await Frax.deploy(0);
        fraxAddress = deployedFrax.address;
        await sleep(5000);
    } else {
        console.log("init Frax by address: %s", fraxAddress);
        deployedFrax = Frax.attach(fraxAddress).connect(deployer);
    }
    console.log("Frax finish,fraxAddress: %s", fraxAddress);
}


//部署sOHM
async function deploySOHM() {
    const SOHM = await ethers.getContractFactory('sOlympus');  //取用文件内的合约名称
    if (!sohmAddress || sohmAddress == "") {
        console.log("deploy sOlympus start");
        deployedSohm = await SOHM.deploy();
        sohmAddress = deployedSohm.address;
        await sleep(5000);
    } else {
        console.log("init sOlympus by address: %s", sohmAddress);
        deployedSohm = SOHM.attach(sohmAddress).connect(deployer);
    }
    console.log("sOlympus finish,sohmAddress: %s", sohmAddress);
}

//部署staking合约（依赖OHM、sOHM）
async function deployStaking() {
    const Staking = await ethers.getContractFactory('OlympusStaking');
    if (!stakingAddress || stakingAddress == "") {
        console.log("deploy OlympusStaking start");
        deployedStaking = await Staking.deploy(ohmAddress, sohmAddress, epochLengthInBlocks, firstEpochNumber, firstEpochBlock);
        stakingAddress = deployedStaking.address;
        await sleep(5000);
    } else {
        console.log("init OlympusStaking by address: %s", stakingAddress);
        deployedStaking = Staking.attach(stakingAddress).connect(deployer);
    }
    console.log("OlympusStaking finish,stakingAddress: %s", stakingAddress);
}

//部署StakingHelper合约(依赖staking、OHM)
async function deployStakingHelper() {
    const StakingHelper = await ethers.getContractFactory('StakingHelper');
    if (!stakingHelperAddress || stakingHelperAddress == "") {
        console.log("deploy StakingHelper start");
        deployedStakingHelper = await StakingHelper.deploy(stakingAddress, ohmAddress);
        stakingHelperAddress = deployedStakingHelper.address;
        await sleep(5000);
    } else {
        console.log("init StakingHelper by address: %s", stakingHelperAddress);
        deployedStakingHelper = StakingHelper.attach(stakingHelperAddress).connect(deployer);
    }
    console.log("StakingHelper finish,stakingHelperAddress: %s", stakingHelperAddress);
}



//部署StakingWarmup（依赖staking、sOHM）
async function deployStakingWarmup() {
    const StakingWarmpup = await ethers.getContractFactory('StakingWarmup');
    if (!stakingWarmupAddress || stakingWarmupAddress == "") {
        console.log("deploy StakingWarmup start");
        deployedStakingWarmpup = await StakingWarmpup.deploy(stakingAddress, sohmAddress);
        stakingWarmupAddress = deployedStakingWarmpup.address;
        await sleep(5000);
    } else {
        console.log("init StakingWarmup by address: %s", stakingWarmupAddress);
        deployedStakingWarmpup = StakingWarmpup.attach(stakingWarmupAddress).connect(deployer);
    }
    console.log("StakingWarmup finish,stakingWarmupAddress: %s", stakingWarmupAddress);
}


//部署OlympusBondingCalculator（依赖OHM）
async function deployOlympusBondingCalculator() {
    const OlympusBondingCalculator = await ethers.getContractFactory('OlympusBondingCalculator');
    if (!olympusBondingCalculatorAddress || olympusBondingCalculatorAddress == "") {
        console.log("deploy OlympusBondingCalculator start");
        deployedOlympusBondingCalculator = await OlympusBondingCalculator.deploy(ohmAddress);
        olympusBondingCalculatorAddress = deployedOlympusBondingCalculator.address;
        await sleep(5000);
    } else {
        console.log("init OlympusBondingCalculator by address: %s", olympusBondingCalculatorAddress);
        deployedOlympusBondingCalculator = OlympusBondingCalculator.attach(olympusBondingCalculatorAddress).connect(deployer);
    }
    console.log("OlympusBondingCalculator finish,olympusBondingCalculatorAddress: %s", olympusBondingCalculatorAddress);
}

//部署MockOlympusTreasury(依赖：OHM、DAI、frax)------生产需要根据实际支持的Treasury来调整构造函数入参的Token
async function deployMockOlympusTreasury() {
    const Treasury = await ethers.getContractFactory('MockOlympusTreasury');
    if (!treasuryAddress || treasuryAddress == "") {
        console.log("deploy MockOlympusTreasury start");
        // deployedTreasury = await Treasury.deploy(ohmAddress, daiAddress, fraxAddress, 0); 
        deployedTreasury = await Treasury.deploy(ohmAddress, daiAddress, 0); // TODO 比原来案例减少了fraxToken参数
        treasuryAddress = deployedTreasury.address;
        await sleep(5000);
    } else {
        console.log("init MockOlympusTreasury by address: %s", treasuryAddress);
        deployedTreasury = Treasury.attach(treasuryAddress).connect(deployer);
    }
    console.log("MockOlympusTreasury finish,treasuryAddress: %s", treasuryAddress);
}

//部署Distributor(依赖Treasury、OHM)
async function deployDistributor() {
    const Distributor = await ethers.getContractFactory('Distributor');
    if (!distributorAddress || distributorAddress == "") {
        console.log("deploy Distributor start");
        deployedDistributor = await Distributor.deploy(treasuryAddress, ohmAddress, epochLengthInBlocks, firstEpochBlock);
        distributorAddress = deployedDistributor.address;
        await sleep(5000);
    } else {
        console.log("init Distributor by address: %s", distributorAddress);
        deployedDistributor = Distributor.attach(distributorAddress).connect(deployer);
    }
    console.log("Distributor finish,distributorAddress: %s", distributorAddress);
}

//部署一些bondDepository（生产按实际初始化相关资产地址）
async function deployBondDepository() {
    const DaiBondDepository = await ethers.getContractFactory('MockOlympusBondDepository');
    if (!daiBondAddress || daiBondAddress == "") {
        console.log("deploy MockOlympusBondDepository start");
        deployedDaiBond = await DaiBondDepository.deploy(ohmAddress, daiAddress, treasuryAddress, mockDaoAddress, zeroAddress);
        daiBondAddress = deployedDaiBond.address;
        await sleep(5000);
    } else {
        console.log("init deployedDaiBond by address: %s", daiBondAddress);
        deployedDaiBond = DaiBondDepository.attach(daiBondAddress).connect(deployer);
    }
    console.log("DaiBondDepository finish,daiBondAddress: %s", daiBondAddress);

    const FraxBondDepository = await ethers.getContractFactory('MockOlympusBondDepository');
    if (!fraxBondAddress || fraxBondAddress == "") {
        console.log("deploy MockOlympusBondDepository start");
        deployedFraxBond = await FraxBondDepository.deploy(ohmAddress, fraxAddress, treasuryAddress, mockDaoAddress, zeroAddress);
        fraxBondAddress = deployedFraxBond.address;
        await sleep(5000);
    } else {
        console.log("init deployedFraxBond by address: %s", fraxBondAddress);
        deployedFraxBond = FraxBondDepository.attach(fraxBondAddress).connect(deployer);
    }
    console.log("FraxBondDepository finish,fraxBondAddress: %s", fraxBondAddress);

}

async function main() {
    [deployer] = await ethers.getSigners();
    deployerAddress = deployer.address;

    //打印参数
    await defaultAndPrintParam();
    //部署OHM
    await deployOHM();
    //部署DAI
    await deployDAI();
    //部署deployFrax
    // await deployFrax();
    //部署sOHM
    await deploySOHM();
    //部署staking合约（依赖OHM、sOHM）
    await deployStaking();
    //部署StakingHelper合约(依赖staking、OHM)
    await deployStakingHelper();
    //部署StakingWarmup（依赖staking、sOHM）
    await deployStakingWarmup();
    //部署OlympusBondingCalculator（依赖OHM）
    await deployOlympusBondingCalculator();
    //部署MockOlympusTreasury(依赖：OHM、DAI、frax)------生产需要根据实际支持的Treasury来调整构造函数入参的Token
    await deployMockOlympusTreasury();
    //部署Distributor(依赖Treasury、OHM)
    await deployDistributor();
    //部署一些bondDepository（这里部署了质押dai和frax的BondDepository）（生产按实际初始化相关资产地址）
    await deployBondDepository();


    // 铸币（测试用）【Deploy 10,000,000 mock DAI and mock Frax】
    await waitTrans(await deployedDai.mint(deployerAddress, initialMint), "daiMintTrans");
    // await waitTrans(await deployedFrax.mint(deployerAddress, initialMint), "fraxMintTrans");


    // TODO queue and toggle DAI and Frax bond reserve depositor
    await waitTrans(await deployedTreasury.queue('0', daiBondAddress), "Treasury queue 0 daiBond");
    // await waitTrans(await deployedTreasury.queue('0', fraxBondAddress), "Treasury queue 0 fraxBond");
    await waitTrans(await deployedTreasury.toggle('0', daiBondAddress, zeroAddress), "Treasury toggle 0 daiBond");
    // await waitTrans(await deployedTreasury.toggle('0', fraxBondAddress, zeroAddress), "Treasury toggle 0 fraxBond");

    // 配置债券信息（如：最低价、最大单笔交易等）【Set DAI and Frax bond terms】
    await waitTrans(await deployedDaiBond.initializeBondTerms(daiBondBCV, bondVestingLength, minBondPrice, maxBondPayout, bondFee, maxBondDebt, intialBondDebt), "daiBond initializeBondTerms");
    // await waitTrans(await deployedFraxBond.initializeBondTerms(fraxBondBCV, bondVestingLength, minBondPrice, maxBondPayout, bondFee, maxBondDebt, intialBondDebt), "fraxBond initializeBondTerms");

    // TODO 配置staking合约地址【Set staking for DAI and Frax bond】  TODO stakingAddress可以是staking或stakingHelper合约， 第二个入参是bool
    await waitTrans(await deployedDaiBond.setStaking(stakingAddress, stakingHelperAddress), "daiBond setStaking");
    // await waitTrans(await deployedFraxBond.setStaking(stakingAddress, stakingHelperAddress), "fraxBond setStaking");

    // sOHM初始化参数【Initialize sOHM and set the index】
    await waitTrans(await deployedSohm.initialize(stakingAddress), "sOhm initialize");
    await waitTrans(await deployedSohm.setIndex(initialIndex), "sOhm setIndex");

    // 配置合约地址【set distributor contract and warmup contract】
    await waitTrans(await deployedStaking.setContract('0', distributorAddress), "staking set DistributorAddress");
    await waitTrans(await deployedStaking.setContract('1', stakingWarmupAddress), "staking set StakingWarmupAddress");

    // 给OHM合约地址设置treasury合约地址【Set treasury for OHM token】
    await waitTrans(await deployedOHM.setVault(treasuryAddress), "ohm set treasuryAddress");

    // ！！！！！！！这一步相当重要，关系到给用户的收益
    // 在distributor合约设置每次rebase时，给staking合铸币的比例【 Add staking contract as distributor recipient】
    // 每次rebase给stakingmint的用于staker分红的OHM份额：IERC20(OHM).totalSupply().mul(_rate).div(1000000)
    await waitTrans(await deployedDistributor.addRecipient(stakingAddress, initialRewardRate), "DistributorContract addRecipient");

    // queue and toggle reward manager 
    await waitTrans(await deployedTreasury.queue('8', distributorAddress), "Treasury queue 8 distributorAddress");
    await waitTrans(await deployedTreasury.toggle('8', distributorAddress, zeroAddress), "Treasury toggle 8 distributorAddress");

    //------------
    //以下可能是测试
    //------------

    // queue and toggle deployer reserve depositor
    await waitTrans(await deployedTreasury.queue('0', deployerAddress), "Treasury queue 0 deployerAddress");
    await waitTrans(await deployedTreasury.toggle('0', deployerAddress, zeroAddress), "Treasury toggle 0 deployerAddress");

    // queue and toggle liquidity depositor
    await waitTrans(await deployedTreasury.queue('4', deployerAddress,), "Treasury queue 4 deployerAddress");
    await waitTrans(await deployedTreasury.toggle('4', deployerAddress, zeroAddress), "Treasury toggle 4 deployerAddress");

    // Approve the treasury to spend DAI and Frax
    await waitTrans(await deployedDai.approve(treasuryAddress, largeApproval), "dai approve treasuryAddress");
    // await waitTrans(await deployedFrax.approve(treasuryAddress, largeApproval), "frax approve treasuryAddress");

    // Approve dai and frax bonds to spend deployer's DAI and Frax
    await waitTrans(await deployedDai.approve(daiBondAddress, largeApproval), "dai approve daiBondAddress");
    // await waitTrans(await deployedFrax.approve(fraxBondAddress, largeApproval), "frax approve fraxBondAddress");

    // Approve staking and staking helper contact to spend deployer's OHM
    await waitTrans(await deployedOHM.approve(stakingAddress, largeApproval), "ohm approve stakingAddress");
    await waitTrans(await deployedOHM.approve(stakingHelperAddress, largeApproval), "ohm approve stakingHelperAddress");

    // Deposit 9,000,000 DAI to treasury, 600,000 OHM gets minted to deployer and 8,400,000 are in treasury as excesss reserves
    await waitTrans(await deployedTreasury.deposit('9000000000000000000000000', daiAddress, '8400000000000000'), "Treasury deposit dai");

    // Deposit 5,000,000 Frax to treasury, all is profit and goes as excess reserves
    await waitTrans(await deployedTreasury.deposit('5000000000000000000000000', fraxAddress, '5000000000000000'), "Treasury deposit frax");

    // Stake OHM through helper
    await waitTrans(await deployedStakingHelper.stake('100000000000'), "stakingHelper stake");

    // Bond 1,000 OHM and Frax in each of their bonds
    await waitTrans(await deployedDaiBond.deposit('1000000000000000000000', '60000', deployerAddress), "deployedDaiBond deposit deployerAddress");
    // await waitTrans(await deployedFraxBond.deposit('1000000000000000000000', '60000', deployerAddress), "deployedFraxBond deposit deployerAddress");


    console.log("deploy finish");
}

main()
    .then(() => process.exit())
    .catch(error => {
        console.error(error);
        process.exit(1);
    })




function sleep(ms) {
    console.log(moment().format("YYYYMMDD HH:mm:ss"), 'DEBUG', 'sleep ms ' + ms);
    return new Promise((resolve) => {
        setTimeout(resolve, ms);
    });
}

async function waitTrans(trans, transDesc) {
    console.log("%s start", transDesc);
    await trans.wait();
    await sleep(5000);
    console.log("%s success", transDesc);
}