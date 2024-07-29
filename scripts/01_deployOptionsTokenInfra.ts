import { ethers, upgrades } from "hardhat";
import { getImplementationAddress } from '@openzeppelin/upgrades-core';
import config from './config.json';



async function main() {
  const swapper = await ethers.getContractAt("ReaperSwapper", config.SWAPPER);
  const contractsToDeploy = config.CONTRACTS_TO_DEPLOY;
  const thenaPair = config.ORACLE_SOURCE;
  const targetToken = config.OT_UNDERLYING_TOKEN;
  const owner = config.OWNER;
  const secs = config.ORACLE_SECS;
  const minPrice = config.ORACLE_MIN_PRICE;

  const veloRouter = config.VELO_ROUTER;
  const addressProvider = config.ADDRESS_PROVIDER;

  //Oracle
  let oracle;
  if(contractsToDeploy.includes("ThenaOracle")){
    oracle = await ethers.deployContract(
      "ThenaOracle",
      [thenaPair, targetToken, owner, secs, minPrice]
    );
    await oracle.waitForDeployment();
    console.log(`Oracle deployed to: ${await oracle.getAddress()}`);
  }
  else{
    try{
      oracle = await ethers.getContractAt("ThenaOracle", config.ORACLE);
    }
    catch(error){
      console.log("ThenaOracle NOT available due to lack of configuration");
    }
  }
 
  // OptionsToken
  let optionsToken;
  if(contractsToDeploy.includes("OptionsToken")){
    const tokenName = config.OT_NAME;
    const symbol = config.OT_SYMBOL;
    const tokenAdmin = config.OT_TOKEN_ADMIN;
    const OptionsToken = await ethers.getContractFactory("OptionsToken");
    optionsToken = await upgrades.deployProxy(
      OptionsToken,
      [tokenName, symbol, tokenAdmin],
      { kind: "uups", initializer: "initialize" }
    );
  
    await optionsToken.waitForDeployment();
    console.log(`OptionsToken deployed to: ${await optionsToken.getAddress()}`);
    console.log(`Implementation: ${await getImplementationAddress(ethers.provider, await optionsToken.getAddress())}`);
  }
  else{
    try{
      optionsToken = await ethers.getContractAt("OptionsToken", config.OPTIONS_TOKEN);
    }
    catch(error){
      console.log("OptionsToken NOT available due to lack of configuration");
    }    
  }

  const swapProps = {
    swapper: await swapper.getAddress(),
    exchangeAddress: veloRouter,
    exchangeTypes: 2, /* VeloSolid */
    maxSwapSlippage: 500 /* 5% */
  };

  // Exercise
  let exercise;
  if(contractsToDeploy.includes("DiscountExercise")){
    const paymentToken = config.OT_PAYMENT_TOKEN;
    const multiplier = config.MULTIPLIER;
    const feeRecipients = String(config.FEE_RECIPIENTS).split(",");
    const feeBps = String(config.FEE_BPS).split(",");
    const instantExitFee = config.INSTANT_EXIT_FEE;
    const minAmountToTriggerSwap = config.MIN_AMOUNT_TO_TRIGGER_SWAP;
  
    exercise = await ethers.deployContract(
      "DiscountExercise",
      [
        await optionsToken.getAddress(),
        owner,
        paymentToken,
        targetToken,
        await oracle.getAddress(),
        multiplier,
        instantExitFee,
        minAmountToTriggerSwap,
        feeRecipients,
        feeBps,
        swapProps
      ]
    );
    await exercise.waitForDeployment();
    console.log(`Exercise deployed to: ${await exercise.getAddress()}`);
  
    // Set exercise
    const exerciseAddress = await exercise.getAddress();
    await optionsToken.setExerciseContract(exerciseAddress, true);
    console.log(`Exercise set to: ${exerciseAddress}`);
  }
  else{
    try{
      exercise = await ethers.getContractAt("DiscountExercise", config.DISCOUNT_EXERCISE);
    }
    catch(error){
      console.log("DiscountExercise NOT available due to lack of configuration");
    }

  }


  // OptionsCompounder
  let optionsCompounder;
  const strats = String(config.STRATS).split(",");
  if(contractsToDeploy.includes("OptionsCompounder")){

    const OptionsCompounder = await ethers.getContractFactory("OptionsCompounder");
  
    // console.log("Proxy deployment: ", [optionsToken, addressProvider, swapper, swapProps, oracle]);
    console.log("Proxy deployment: ", [await optionsToken.getAddress(), addressProvider, await swapper.getAddress(), swapProps, await oracle.getAddress(), strats]);
    
    optionsCompounder = await upgrades.deployProxy(
      OptionsCompounder,
      [await optionsToken.getAddress(), addressProvider, await swapper.getAddress(), swapProps, await oracle.getAddress(), strats],
      { kind: "uups", initializer: "initialize" }
    );
  
    // const optionsCompounder = await upgrades.deployProxy(
    //   OptionsCompounder,
    //   [optionsToken, addressProvider, swapper, swapProps, oracle],
    //   { kind: "uups", initializer: "initialize" }
    // );
  
    await optionsCompounder.waitForDeployment();
    console.log(`OptionsCompounder deployed to: ${await optionsCompounder.getAddress()}`);
    console.log(`Implementation: ${await getImplementationAddress(ethers.provider, await optionsCompounder.getAddress())}`);
  }
  else{
    try{
      optionsCompounder = await ethers.getContractAt("OptionsCompounder", config.OPTIONS_COMPOUNDER);
      await optionsCompounder.setStrats(strats);
    }
    catch(error){
      console.log("OptionsCompounder NOT available due to lack of configuration");
    }
  }

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
