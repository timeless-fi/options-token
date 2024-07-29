import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import '@openzeppelin/hardhat-upgrades';
import "@nomicfoundation/hardhat-foundry";
import glob from "glob";
import {TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS} from "hardhat/builtin-tasks/task-names";
import path from "path";
import { subtask } from "hardhat/config";

import { config as dotenvConfig } from "dotenv";

// import "@nomiclabs/hardhat-ethers";
import "@nomicfoundation/hardhat-verify";
import "hardhat-contract-sizer";

dotenvConfig();

const PRIVATE_KEY = process.env.PRIVATE_KEY || "";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.19",
    settings: {
      optimizer: { enabled: true, runs: 200 }
    }
  },
  sourcify: {
    enabled: true
  },
  paths: {
    sources: "./src",
    tests: "./test_hardhat",
  },
  networks: {
    op: {
      url: "https://mainnet.optimism.io",
      chainId: 10,
      accounts: [`0x${PRIVATE_KEY}`],
    },
    bsc: {
      url: "https://bsc-dataseed.binance.org/",
      chainId: 56,
      accounts: [`0x${PRIVATE_KEY}`],
    },
    mode: {
      url: "https://mainnet.mode.network/",
      chainId: 34443,
      accounts: [`0x${PRIVATE_KEY}`],
    },
  },
  etherscan: {
    apiKey: { 
      bsc: process.env.ETHERSCAN_KEY || "",
    },
    // customChains: [
    //   {
    //     network: "mode",
    //     chainId: 34443,
    //     urls: {
    //       apiURL: "https://explorer.mode.network",
    //       browserURL: "https://explorer.mode.network"
    //     }
    //   }
    // ]
  },

};

subtask(TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS).setAction(async (_, hre, runSuper) => {
  const paths = await runSuper();

  const otherDirectoryGlob = path.join(hre.config.paths.root, "test", "**", "*.sol");
  const otherPaths = glob.sync(otherDirectoryGlob);

  return [...paths, ...otherPaths];
});

export default config;
