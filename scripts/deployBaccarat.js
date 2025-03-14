const { ethers } = require('hardhat');
const args = require('./arguments')

async function main() {
  const [deployer] = await ethers.getSigners(); // Get deployer

  const balance = await ethers.provider.getBalance(deployer.address); // Get balance deployer

  console.log(`Deployer Address: ${deployer.address}`);
  console.log(`Balance: ${ethers.formatEther(balance)} ETH`);

  const Baccarat = await ethers.deployContract("Baccarat", args);

  await Baccarat.waitForDeployment();

  console.log("Baccarat deployed to:", await Baccarat.getAddress());
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });