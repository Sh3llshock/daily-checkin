const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);

  const AccessToken = await hre.ethers.getContractFactory("AccessToken");
  const accessToken = await AccessToken.deploy();
  await accessToken.waitForDeployment();
  console.log("AccessToken deployed to:", await accessToken.getAddress());

  const DigitalIdentityRegistry = await hre.ethers.getContractFactory("DigitalIdentityRegistry");
  const registry = await DigitalIdentityRegistry.deploy();
  await registry.waitForDeployment();
  console.log("DigitalIdentityRegistry deployed to:", await registry.getAddress());

  const ConsentManager = await hre.ethers.getContractFactory("ConsentManager");
  const consentManager = await ConsentManager.deploy(
    await registry.getAddress(),
    await accessToken.getAddress()
  );
  await consentManager.waitForDeployment();
  console.log("ConsentManager deployed to:", await consentManager.getAddress());

  const AccessLogger = await hre.ethers.getContractFactory("AccessLogger");
  const accessLogger = await AccessLogger.deploy();
  await accessLogger.waitForDeployment();
  console.log("AccessLogger deployed to:", await accessLogger.getAddress());

  const DataSharingManager = await hre.ethers.getContractFactory("DataSharingManager");
  const dataSharingManager = await DataSharingManager.deploy(
    await registry.getAddress(),
    await consentManager.getAddress(),
    await accessLogger.getAddress()
  );
  await dataSharingManager.waitForDeployment();
  console.log("DataSharingManager deployed to:", await dataSharingManager.getAddress());

  // Wire the contracts together.
  await (await accessToken.setMinter(await consentManager.getAddress())).wait();
  await (await accessLogger.setDataSharingManager(await dataSharingManager.getAddress())).wait();

  console.log("\nDeployment + wiring complete.");
  console.log({
    AccessToken: await accessToken.getAddress(),
    DigitalIdentityRegistry: await registry.getAddress(),
    ConsentManager: await consentManager.getAddress(),
    AccessLogger: await accessLogger.getAddress(),
    DataSharingManager: await dataSharingManager.getAddress(),
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
