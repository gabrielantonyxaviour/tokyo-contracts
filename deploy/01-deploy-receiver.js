const verify = require("../helper-functions");
const { developmentChains } = require("../helper-hardhat-config");
const { ethers } = require("hardhat");

const deployReceiver = async function (hre) {
  // @ts-ignore
  const { getNamedAccounts, deployments, network } = hre;
  const { deploy, log } = deployments;
  const { deployer } = await getNamedAccounts();
  log("----------------------------------------------------");
  log("Deploying Receiver and waiting for confirmations...");
  const receiver = await deploy("Receiver", {
    from: deployer,
    args: [],
    log: true,
    waitConfirmations: developmentChains.includes(network.name) ? 1 : 5,
  });
  log(`Receiver at ${receiver.address}`);
  if (
    !developmentChains.includes(network.name) &&
    process.env.ETHERSCAN_API_KEY
  ) {
    await verify(receiver.address, []);
  }
};

module.exports = deployReceiver;
deployReceiver.tags = ["all", "receiver"];
