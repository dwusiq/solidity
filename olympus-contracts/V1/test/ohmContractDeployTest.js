const { ethers } = require('hardhat');

//部署ohm
async function deployOHM() {
    const OHM = await ethers.getContractFactory('OlympusERC20Token');
    let deployedOHM = await OHM.deploy();
    console.log("ohm deploy finish, ohmAddress: %s", deployedOHM.address);
    return deployedOHM;
}

//部署sOHM
async function deploySOHM() {
    const sOHM = await ethers.getContractFactory('sOlympus');  //取用文件内的合约名称
    let deployedSOHM = await sOHM.deploy();
    console.log("sOHM deploy finish, sohmAddress: %s", deployedSOHM.address);
    return deployedSOHM;
}

//部署DAI
async function deployDAI() {
    const DAI = await ethers.getContractFactory('DAI');
    let deployedDai = await DAI.deploy(0);
    console.log("DAI deploy finish, daiAddress: %s", deployedDai.address);
    return deployedDai;
}


//部署staking合约（依赖OHM、sOHM）
async function deployStaking(ohmAddress, sOhmAddress, epochLengthInBlocks, firstEpochNumber, firstEpochBlock) {
    const Staking = await ethers.getContractFactory('OlympusStaking');
    const deployedStaking = await Staking.deploy(ohmAddress, sOhmAddress, epochLengthInBlocks, firstEpochNumber, firstEpochBlock);
    console.log("Staking deploy finish, stakingAddress: %s", deployedStaking.address);
    return deployedStaking;
}


//部署StakingWarmup（依赖staking、sOHM）
async function deployStakingWarmup(stakingAddress, sohmAddress) {
    const StakingWarmpup = await ethers.getContractFactory('StakingWarmup');
    const deployedStakingWarmpup = await StakingWarmpup.deploy(stakingAddress, sohmAddress);
    console.log("StakingWarmup deploy finish,stakingWarmupAddress: %s", deployedStakingWarmpup.address);
    return deployedStakingWarmpup;
}

//部署StakingWarmup（依赖staking、sOHM）
async function deployStakingHelper(stakingAddress, ohmAddress) {
    const StakingHelper = await ethers.getContractFactory('StakingHelper');
    const deployedStakingHelper = await StakingHelper.deploy(stakingAddress, ohmAddress);
    console.log("StakingHelper deploy finish,stakingHelperAddress: %s", deployedStakingHelper.address);
    return deployedStakingHelper;
}


//部署MockOlympusTreasury(依赖：OHM、DAI)------生产需要根据实际支持的Treasury来调整构造函数入参的Token
async function deployTreasury(ohmAddress, daiAddress, blocksNeededForQueue) {
    const Treasury = await ethers.getContractFactory('MockOlympusTreasury');
    const deployedTreasury = await Treasury.deploy(ohmAddress, daiAddress, blocksNeededForQueue); // TODO 比原来案例减少了fraxToken
    console.log("MockOlympusTreasury deploy finish,treasuryAddress: %s", deployedTreasury.address);
    return deployedTreasury;
}

//部署Distributor(依赖：OHM、treasury)
async function deployDistributor(treasuryAddress, ohmAddress, epochLengthInBlocks, firstEpochBlock) {
    const Distributor = await ethers.getContractFactory('Distributor');
    const deployedDistributor = await Distributor.deploy(treasuryAddress, ohmAddress, epochLengthInBlocks, firstEpochBlock);
    console.log("StakingDistributor deploy finish,distributorAddress: %s", deployedDistributor.address);
    return deployedDistributor;
}


//部署DaiBondDepository（生产按实际初始化相关资产地址）
async function deployDaiBond(ohmAddress, daiAddress, treasuryAddress, daoAddress, zeroAddress) {
    const DaiBondDepository = await ethers.getContractFactory('MockOlympusBondDepository');
    const deployedDaiBond = await DaiBondDepository.deploy(ohmAddress, daiAddress, treasuryAddress, daoAddress, zeroAddress);
    console.log("DaiBondDepository deploy finish,deployedDaiBondAddress: %s", deployedDaiBond.address);
    return deployedDaiBond;
}


//只有在支持lp质押时才部署OlympusBondingCalculator（依赖OHM）
async function deployOlympusBondingCalculator(ohmAddress) {
    const OlympusBondingCalculator = await ethers.getContractFactory('OlympusBondingCalculator');
    const deployedCalculator = await OlympusBondingCalculator.deploy(ohmAddress);
    console.log("OlympusBondingCalculator deploy finish,calculatorBondAddress: %s", deployedCalculator.address);
    return deployedCalculator;
}



/**
 * 部署OHMPresale，用户参与预售
 */
async function deployOHMPresale() {
    const OHMPresale = await ethers.getContractFactory('OHMPresale');
    const deployedOHMPresale = await OHMPresale.deploy();
    console.log("OHMPresale deploy finish,oHMPreSaleAddress: %s", deployedOHMPresale.address);
    return deployedOHMPresale;
}


/**
 * 部署AlphaOHM，用于预售支付给用户的代币
 */
async function deployAlphaOHM() {
    const AlphaOHM = await ethers.getContractFactory('AlphaOHM');
    const deployedAlphaOHM = await AlphaOHM.deploy();
    console.log("AlphaOHM deploy finish,alphaOHMAddress: %s", deployedAlphaOHM.address);
    return deployedAlphaOHM;
}

/**
 * 部署deployedAohmMigration用于支持参与预售的用户兑换OHM.
 */
async function deployAohmMigration() {
    const AohmMigration = await ethers.getContractFactory('AohmMigration');
    const deployedAohmMigration = await AohmMigration.deploy();
    console.log("AohmMigration deploy finish,aohmMigrationAddress: %s", deployedAohmMigration.address);
    return deployedAohmMigration;
}





module.exports = {
    deployOHM,
    deploySOHM,
    deployDAI,
    deployStaking,
    deployStakingWarmup,
    deployStakingHelper,
    deployTreasury,
    deployDistributor,
    deployDaiBond,
    deployOlympusBondingCalculator,
    deployAlphaOHM,
    deployAohmMigration,
    deployOHMPresale
}