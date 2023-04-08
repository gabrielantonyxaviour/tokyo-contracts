const { run } = require("hardhat");
const util = require("util");

const request = util.promisify(require("request"));

const verify = async (contractAddress, args) => {
  console.log(`Verfiying contract: ${contractAddress}`);

  try {
    await run("verify:verify", {
      address: contractAddress,
      constructorArguments: args,
    });
  } catch (e) {
    if (e.message.toLowerCase().includes("already verified")) {
      console.log("Contract already verified");
    } else {
      console.log(e);
    }
  }
};

module.exports = verify;
