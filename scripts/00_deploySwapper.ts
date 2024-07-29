import { ethers, upgrades } from "hardhat";
import config from './config.json';

async function main() {
    const contractsToDeploy = config.CONTRACTS_TO_DEPLOY;
    const paymentToken = config.OT_PAYMENT_TOKEN;
    const underlyingToken = config.OT_UNDERLYING_TOKEN;
    const veloRouter = config.VELO_ROUTER;
    const path1 = [{
        from: paymentToken,
        to: underlyingToken,
        stable: false,
    }];

    const path2 = [{
        from: underlyingToken,
        to: paymentToken,
        stable: false,
    }];

    const strategists: string[] = [
        "0x1E71AEE6081f62053123140aacC7a06021D77348", // bongo
        "0x81876677843D00a7D792E1617459aC2E93202576", // degenicus
        "0x4C3490dF15edFa178333445ce568EC6D99b5d71c", // eidolon
        "0xb26cd6633db6b0c9ae919049c1437271ae496d15", // zokunei
        "0x60BC5E0440C867eEb4CbcE84bB1123fad2b262B1", // goober
    ];
    const multisigRoles: string[] = [
        "0x90c75c11735A7eeeD06E993fC7aF6838d86A1Ba7", // super admin
        "0xC17DfA7Eb4300871D5f022c107E07F98c750472e", // admin
        "0x30d65Ae22BBbe44208Dd8964DDE31Def0Fc1B9ee", // guardian
    ];

    // ReaperSwapper
    let swapper;
    if(contractsToDeploy.includes("Swapper")){
        const Swapper = await ethers.getContractFactory("ReaperSwapper");
        const initializerArguments = [
        strategists,
        multisigRoles[2],
        multisigRoles[0],
        ];
        swapper = await upgrades.deployProxy(
        Swapper,
        initializerArguments,
        { kind: "uups", timeout: 0 },
        );
    
        await swapper.waitForDeployment();
        console.log("Swapper deployed to:", await swapper.getAddress());
    }
    else {
        swapper = await ethers.getContractAt("ReaperSwapper", config.SWAPPER); 
    }

    await swapper.updateVeloSwapPath(paymentToken, underlyingToken, veloRouter, path1);
    await swapper.updateVeloSwapPath(underlyingToken, paymentToken, veloRouter, path2);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });