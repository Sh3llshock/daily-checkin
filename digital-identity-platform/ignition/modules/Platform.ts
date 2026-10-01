import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

// Deploys the 4 contracts in the right order and connects them.
export default buildModule("PlatformModule", (m) => {
  const token = m.contract("AccessToken");
  const identity = m.contract("DigitalIdentity");
  const consentManager = m.contract("ConsentManager", [identity, token]);
  const dataSharing = m.contract("DataSharing", [identity, consentManager]);

  // only the ConsentManager is allowed to mint reward tokens
  m.call(token, "setMinter", [consentManager]);

  return { token, identity, consentManager, dataSharing };
});
