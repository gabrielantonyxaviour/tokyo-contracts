const { ethers, network } = require("hardhat");

const propose = async (
  name,
  symbol,
  destinationDomain,
  claimsPerPerson,
  badgeURI
) => {
  const receiver = await ethers.getContractAt(
    "Receiver",
    "0x5B66F6276D1784eD5C5e65566683Bc003758219C"
  );
  const args = [name, symbol, destinationDomain, claimsPerPerson, badgeURI];
  console.log(`Proposing createPromotion on ${receiver.address} with ${args}`);

  const receiverTx = await receiver.createPromotion(
    name,
    symbol,
    destinationDomain,
    claimsPerPerson,
    badgeURI
  );
  const receiverReceipt = await receiverTx.wait(1);
  console.log(receiverReceipt);
};

propose(
  "Go Go Apes",
  "GGA",
  5,
  2,
  "https://ipfs.io/ipfs/bafybeibv36rkxbqbea7k5jzjtg7t73pegmfn4xebmnlfx66p5eioegylwa",
  69,
  100000
)
  .then(() => {
    process.exit(0);
  })
  .catch((err) => {
    console.log(err);
    process.exit(1);
  });
