import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

/**
 * Deploys all 5 contracts in dependency order and wires them together.
 * Replaces the Hardhat 2 scripts/deploy.js.
 */
export default buildModule("DigitalIdentityPlatform", (m) => {
  const accessToken = m.contract("AccessToken");
  const registry = m.contract("DigitalIdentityRegistry");
  const consentManager = m.contract("ConsentManager", [registry, accessToken]);
  const accessLogger = m.contract("AccessLogger");
  const dataSharingManager = m.contract("DataSharingManager", [
    registry,
    consentManager,
    accessLogger,
  ]);

  // Wiring: only ConsentManager may mint ACT, only DataSharingManager may log.
  m.call(accessToken, "setMinter", [consentManager]);
  m.call(accessLogger, "setDataSharingManager", [dataSharingManager]);

  return { accessToken, registry, consentManager, accessLogger, dataSharingManager };
});
