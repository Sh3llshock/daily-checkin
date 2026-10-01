import { network } from "hardhat";
import { keccak256, sha256, toHex } from "viem";
import fs from "node:fs";

// Measures deployment cost and gas per function in a fixed scenario.
// Run: npx hardhat run scripts/gas-report.ts
// Set GAS_LABEL=before / after to name the output file.

const label = process.env.GAS_LABEL ?? "latest";
const gasUsed: Record<string, bigint[]> = {};

function record(name: string, gas: bigint) {
  if (!gasUsed[name]) gasUsed[name] = [];
  gasUsed[name].push(gas);
}

async function main() {
  const { viem } = await network.connect();
  const publicClient = await viem.getPublicClient();
  const wallets = await viem.getWalletClients();
  const admin = wallets[0];
  const doctors = wallets.slice(1, 3);
  const patients = wallets.slice(3, 13); // 10 patients

  async function send(name: string, hashPromise: Promise<`0x${string}`>) {
    const receipt = await publicClient.waitForTransactionReceipt({ hash: await hashPromise });
    record(name, receipt.gasUsed);
    return receipt;
  }

  async function deploy(name: string, args: any[] = []) {
    const { contract, deploymentTransaction } = await viem.sendDeploymentTransaction(name, args);
    const receipt = await publicClient.waitForTransactionReceipt({ hash: deploymentTransaction.hash });
    record("deploy " + name, receipt.gasUsed);
    return contract as any;
  }

  const token = await deploy("AccessToken");
  const identity = await deploy("DigitalIdentity");
  const consent = await deploy("ConsentManager", [identity.address, token.address]);
  const sharing = await deploy("DataSharing", [identity.address, consent.address]);
  await send("setMinter", token.write.setMinter([consent.address]));

  for (const d of doctors) {
    await send("approveRequester", identity.write.approveRequester([d.account.address]));
  }

  for (let i = 0; i < patients.length; i++) {
    const p = patients[i];
    await send("registerUser", identity.write.registerUser(
      [keccak256(toHex("salt" + i)), "vault://patient" + i, sha256(toHex("front" + i)), sha256(toHex("back" + i))],
      { account: p.account },
    ));
  }

  // first request per patient is a denied one (no consent yet)
  for (const p of patients) {
    await send("requestAccess (denied, first entry)", sharing.write.requestAccess([p.account.address], { account: doctors[0].account }));
  }

  for (const p of patients) {
    await send("grantConsent (first, with reward)", consent.write.grantConsent([doctors[0].account.address, 2, 30n], { account: p.account }));
  }

  for (let round = 0; round < 3; round++) {
    for (const p of patients) {
      await send("requestAccess (granted)", sharing.write.requestAccess([p.account.address], { account: doctors[0].account }));
    }
  }

  for (const p of patients) {
    await send("requestAccess (denied, not approved)", sharing.write.requestAccess([p.account.address], { account: wallets[15].account }));
  }

  for (const p of patients) {
    await send("revokeConsent", consent.write.revokeConsent([doctors[0].account.address], { account: p.account }));
  }

  for (const p of patients) {
    await send("requestAccess (denied, revoked)", sharing.write.requestAccess([p.account.address], { account: doctors[0].account }));
  }

  for (const p of patients) {
    await send("grantConsent (again, no reward)", consent.write.grantConsent([doctors[0].account.address, 0, 7n], { account: p.account }));
  }

  for (let i = 0; i < patients.length; i++) {
    await send("updateDocument", identity.write.updateDocument(
      ["vault://patient" + i, sha256(toHex("new front" + i)), sha256(toHex("new back" + i))],
      { account: patients[i].account },
    ));
  }

  // print a table and save json
  const rows: any[] = [];
  console.log(`\nGas report (${label})\n`);
  console.log("| Operation | Calls | Min | Avg | Max |");
  console.log("|---|---|---|---|---|");
  for (const [name, values] of Object.entries(gasUsed)) {
    const nums = values.map(Number);
    const avg = Math.round(nums.reduce((a, b) => a + b, 0) / nums.length);
    const min = Math.min(...nums);
    const max = Math.max(...nums);
    rows.push({ name, calls: nums.length, min, avg, max });
    console.log(`| ${name} | ${nums.length} | ${min} | ${avg} | ${max} |`);
  }

  fs.mkdirSync("results", { recursive: true });
  fs.writeFileSync(`results/gas-report-${label}.json`, JSON.stringify(rows, null, 2));
  console.log(`\nSaved results/gas-report-${label}.json`);
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
