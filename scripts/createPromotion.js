const { ethers, network } = require("hardhat");
const propose = async (
  name,
  symbol,
  destinationDomain,
  claimsPerPerson,
  badgeURI,
  _salt,
  gasAmount
) => {
  const promotion = await ethers.getContractAt(
    "PromotionMain",
    "0x81F6e12Ee41e6aF4aCfb0A0C84d0d17a1B382d3b"
  );
  const args = [
    name,
    symbol,
    destinationDomain,
    claimsPerPerson,
    badgeURI,
    _salt,
    gasAmount,
  ];
  console.log(`Creating promotion at ${promotion.address} with ${args}`);
  const relayerFee = (
    await promotion.getQuotedPayment(destinationDomain, gasAmount)
  ).toString();
  console.log("This is the relayer Fee: " + relayerFee);
  const promotionTx = await promotion.createPromotion(
    name,
    symbol,
    destinationDomain,
    claimsPerPerson,
    badgeURI,
    _salt,
    gasAmount,
    { value: relayerFee }
  );
  const promotionReceipt = await promotionTx.wait(1);
  const promotionData = promotionReceipt.logs[6].data.toString();
  // const promotionAddress = ethers.utils.defaultAbiCoder.decode(
  //   ["bytes32", "address", "uint32", "address", "uint256", "uint256", "string"],
  //   ethers.utils.hexDataSlice(promotionData, 7)
  // )[1];
  console.log(
    `Promotion created at Domain ${destinationDomain} with Hyperlane `
  );
};

propose(
  "Go Go Apes",
  "GGA",
  97,
  2,
  "https://ipfs.io/ipfs/bafybeibv36rkxbqbea7k5jzjtg7t73pegmfn4xebmnlfx66p5eioegylwa",
  69,
  1200000
)
  .then(() => {
    process.exit(0);
  })
  .catch((err) => {
    console.log(err);
    process.exit(1);
  });
