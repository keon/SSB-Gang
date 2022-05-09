// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');

  // string memory name,
  // string memory symbol,
  // address payable beneficiary,
  // address payable royaltyReceiver
  // We get the contract to deploy
  const SSB = await hre.ethers.getContractFactory("SSB");
  const ssb = await SSB.deploy(
    "SSB Gang",
    "SSB",
    "0x76cBbaF24a9b9008E534399167b658Ea57F1c750",
    "0x76cBbaF24a9b9008E534399167b658Ea57F1c750"
  );

  await ssb.deployed();

  console.log("ssb deployed to:", ssb.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
