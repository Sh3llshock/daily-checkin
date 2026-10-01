import { network } from "hardhat";
import { formatEther, keccak256, encodePacked, sha256, toHex } from "viem";

// Scope: 0 = FrontOnly, 1 = BackOnly, 2 = Both
const scopeLabel = (i: number) => ["FrontOnly", "BackOnly", "Both"][i] ?? `Unknown(${i})`;
// Reason: 0 = None, 1 = NotApproved, 2 = NoConsent, 3 = Revoked, 4 = Expired
const reasonLabel = (i: number) =>
  ["None", "NotApproved", "NoConsent", "Revoked", "Expired"][i] ?? `Unknown(${i})`;

async function main() {
  console.log("\n================ DIGITAL IDENTITY PLATFORM DEMO ================\n");

  const { viem } = await network.connect();
  const [admin, patient, doctor, stranger] = await viem.getWalletClients();
  const publicClient = await viem.getPublicClient();

  console.log("Participants:");
  console.log("  Admin   :", admin.account.address);
  console.log("  Patient :", patient.account.address);
  console.log("  Doctor  :", doctor.account.address);
  console.log("  Stranger:", stranger.account.address);

  // Step 1: deploy and connect the contracts
  console.log("\nStep 1: Deploying contracts...");
  const token = await viem.deployContract("AccessToken");
  const identity = await viem.deployContract("DigitalIdentity");
  const consentManager = await viem.deployContract("ConsentManager", [identity.address, token.address]);
  const dataSharing = await viem.deployContract("DataSharing", [identity.address, consentManager.address]);
  await publicClient.waitForTransactionReceipt({
    hash: await token.write.setMinter([consentManager.address]),
  });
  console.log("  AccessToken    :", token.address);
  console.log("  DigitalIdentity:", identity.address);
  console.log("  ConsentManager :", consentManager.address);
  console.log("  DataSharing    :", dataSharing.address);

  // Step 2: admin approves the doctor as a requester
  console.log("\nStep 2: Admin approves the doctor as requester...");
  await publicClient.waitForTransactionReceipt({
    hash: await identity.write.approveRequester([doctor.account.address]),
  });
  console.log("  Doctor approved:", await identity.read.isApprovedRequester([doctor.account.address]));

  // Step 3: patient registers with hashes only (fake data, the real
  // files are hashed by the python tool in offchain/)
  console.log("\nStep 3: Patient registers...");
  const salt = keccak256(toHex("demo-salt"));
  const emailHash = keccak256(encodePacked(["bytes32", "string"], [salt, "patient1@example.test"]));
  const frontHash = sha256(toHex("fake front of id"));
  const backHash = sha256(toHex("fake back of id"));
  await publicClient.waitForTransactionReceipt({
    hash: await identity.write.registerUser([emailHash, "vault://patient1", frontHash, backHash], {
      account: patient.account,
    }),
  });
  const user = await identity.read.getUser([patient.account.address]);
  console.log("  Registered, front hash on-chain:", user[1]);

  // Step 4: doctor asks before there is any consent
  console.log("\nStep 4: Doctor requests access without consent...");
  await requestAndPrint(dataSharing, publicClient, patient.account.address, doctor);

  // Step 5: patient grants consent for 30 days
  console.log("\nStep 5: Patient grants consent (Both, 30 days)...");
  await publicClient.waitForTransactionReceipt({
    hash: await consentManager.write.grantConsent([doctor.account.address, 2, 30n], {
      account: patient.account,
    }),
  });
  const balance = await token.read.balanceOf([patient.account.address]);
  console.log("  Consent valid:", await consentManager.read.isConsentValid([patient.account.address, doctor.account.address]));
  console.log("  Patient ACT balance:", formatEther(balance));

  // Step 6: doctor requests again, now it works
  console.log("\nStep 6: Doctor requests access with consent...");
  await requestAndPrint(dataSharing, publicClient, patient.account.address, doctor);

  // Step 7: a stranger that is not approved tries
  console.log("\nStep 7: Stranger (not approved) requests access...");
  await requestAndPrint(dataSharing, publicClient, patient.account.address, stranger);

  // Step 8: patient revokes, doctor is denied
  console.log("\nStep 8: Patient revokes consent...");
  await publicClient.waitForTransactionReceipt({
    hash: await consentManager.write.revokeConsent([doctor.account.address], { account: patient.account }),
  });
  await requestAndPrint(dataSharing, publicClient, patient.account.address, doctor);

  // Step 9: new consent for 7 days, then jump 8 days in time
  console.log("\nStep 9: Patient grants 7 days again, then 8 days pass...");
  await publicClient.waitForTransactionReceipt({
    hash: await consentManager.write.grantConsent([doctor.account.address, 0, 7n], {
      account: patient.account,
    }),
  });
  console.log("  ACT balance (no second reward):", formatEther(await token.read.balanceOf([patient.account.address])));
  const testClient = await viem.getTestClient();
  await testClient.increaseTime({ seconds: 8 * 24 * 60 * 60 });
  await testClient.mine({ blocks: 1 });
  await requestAndPrint(dataSharing, publicClient, patient.account.address, doctor);

  // Step 10: print the audit log of the patient
  console.log("\nStep 10: Audit log of the patient:");
  const logs = await dataSharing.read.getLogs([patient.account.address]);
  logs.forEach((log, i) => {
    const time = new Date(Number(log.timestamp) * 1000).toISOString().slice(0, 16);
    if (log.result === 0) {
      console.log(`  #${i} ${time} GRANTED requester=${log.requester.slice(0, 10)}... scope=${scopeLabel(log.scope)}`);
    } else {
      console.log(`  #${i} ${time} DENIED  requester=${log.requester.slice(0, 10)}... reason=${reasonLabel(log.reason)}`);
    }
  });
  console.log("");
}

async function requestAndPrint(dataSharing: any, publicClient: any, patient: `0x${string}`, requester: any) {
  const hash = await dataSharing.write.requestAccess([patient], { account: requester.account });
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  const granted = await dataSharing.getEvents.AccessGranted({}, { blockHash: receipt.blockHash });
  const denied = await dataSharing.getEvents.AccessDenied({}, { blockHash: receipt.blockHash });
  if (granted.length > 0) {
    console.log(`  GRANTED (scope ${scopeLabel(granted[0].args.scope)}), gas used: ${receipt.gasUsed}`);
  } else if (denied.length > 0) {
    console.log(`  DENIED (reason ${reasonLabel(denied[0].args.reason)}), gas used: ${receipt.gasUsed}`);
  }
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
