const verify = require("../helper-functions");
const { developmentChains } = require("../helper-hardhat-config");
const { ethers } = require("hardhat");

const deployPromotionMain = async function (hre) {
  // @ts-ignore
  const { getNamedAccounts, deployments, network } = hre;
  const { deploy, log } = deployments;
  const { deployer } = await getNamedAccounts();
  log("----------------------------------------------------");
  log("Deploying PromotionMain and waiting for confirmations...");
  const promotion = await deploy("PromotionMain", {
    from: deployer,
    args: [],
    log: true,
    waitConfirmations: developmentChains.includes(network.name) ? 1 : 5,
  });
  log(`PromotionMain at ${promotion.address}`);
  if (
    !developmentChains.includes(network.name) &&
    process.env.ETHERSCAN_API_KEY
  ) {
    await verify(promotion.address, []);
  }
};

module.exports = deployPromotionMain;
deployPromotionMain.tags = ["all", "promotion"];
