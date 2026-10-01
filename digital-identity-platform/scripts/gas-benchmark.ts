/**
 * Gas benchmark for TASKS B5 / A4.
 *
 * `npm run test:gas` reports gas per *function*, mixing every scenario the
 * tests happen to run. This script instead sends each scenario as its own
 * real transaction on Hardhat's in-process network and records the receipt's
 * `gasUsed` (what a user would actually pay: 21,000 base + calldata +
 * execution), so `requestAccess` granted vs denied and a first consent grant
 * vs a re-grant are measured separately.
 *
 * Run with:
 *   npm run gas:bench                                    # print the tables
 *   GAS_BENCH_OUT=docs/gas/bench-after.json npm run gas:bench
 *   GAS_BENCH_LOGGER=EventsOnlyAccessLogger npm run gas:bench   # A4 experiment
 *
 * All identity values are synthetic placeholders -- no personal data.
 *
 * AI-assisted: written with Claude Code (Claude Opus 5.5) on 2026-10-01. Per
 * the coursebook GenAI rules it must be reviewed by the team and declared in
 * the report's AI statement.
 */
import { writeFileSync } from "node:fs";
import { network } from "hardhat";
import { sha256, toHex, type Hash } from "viem";

const USERS = 5; // samples per scenario
const LOGGER = process.env.GAS_BENCH_LOGGER ?? "AccessLogger";
const OUT = process.env.GAS_BENCH_OUT;

// Same link format the off-chain gatekeeper uses, so string storage costs match.
const linkFor = (user: string) => `http://127.0.0.1:8600/users/${user.toLowerCase()}`;

const SCOPE_BOTH = 2;

const { viem } = await network.create();
const publicClient = await viem.getPublicClient();
const testClient = await viem.getTestClient();
const [admin, requesterA, requesterB, ...rest] = await viem.getWalletClients();
const users = rest.slice(0, USERS);

const samples: Record<string, number[]> = {};
const deployment: Record<string, { gas: number; bytecodeSize: number }> = {};

async function gasOf(hash: Hash): Promise<number> {
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  if (receipt.status !== "success") throw new Error(`transaction ${hash} reverted`);
  return Number(receipt.gasUsed);
}

async function record(scenario: string, hash: Hash) {
  (samples[scenario] ??= []).push(await gasOf(hash));
}

async function deploy(name: string, args: `0x${string}`[] = []) {
  const { contract, deploymentTransaction } = await viem.sendDeploymentTransaction(name, args);
  const gas = await gasOf(deploymentTransaction.hash);
  const code = await publicClient.getCode({ address: contract.address });
  deployment[name] = { gas, bytecodeSize: code ? (code.length - 2) / 2 : 0 };
  return contract;
}

// --- Deployment, in the same order as ignition/modules/DigitalIdentityPlatform.ts ---
const token = await deploy("AccessToken");
const registry = await deploy("DigitalIdentityRegistry");
const consent = await deploy("ConsentManager", [registry.address, token.address]);
const logger = await deploy(LOGGER);
const dsm = await deploy("DataSharingManager", [registry.address, consent.address, logger.address]);

await record("setMinter", await token.write.setMinter([consent.address]));
await record("setDataSharingManager", await logger.write.setDataSharingManager([dsm.address]));

// --- Admin whitelists requesters ---
await record("setRequesterStatus (approve)", await registry.write.setRequesterStatus([requesterA.account.address, true]));
await record("setRequesterStatus (approve)", await registry.write.setRequesterStatus([requesterB.account.address, true]));
await record("setRequesterStatus (remove)", await registry.write.setRequesterStatus([requesterB.account.address, false]));
await record("setRequesterStatus (approve)", await registry.write.setRequesterStatus([requesterB.account.address, true]));

const as = (wallet: typeof admin) => ({ account: wallet.account });

for (const [i, user] of users.entries()) {
  const addr = user.account.address;
  const label = `test-user-${i + 1}`;
  const emailHash = sha256(toHex(`${label}@example.invalid`));
  const front = sha256(toHex(`${label}-front`));
  const back = sha256(toHex(`${label}-back`));

  await record("registerUser", await registry.write.registerUser([emailHash, linkFor(addr), front, back], as(user)));
  await record("setConsent (first grant, mints ACT)", await consent.write.setConsent([requesterA.account.address, SCOPE_BOTH, 30n], as(user)));
  await record("requestAccess (granted, 1st log entry)", await dsm.write.requestAccess([addr], as(requesterA)));
  await record("requestAccess (granted, later entry)", await dsm.write.requestAccess([addr], as(requesterA)));
  await record("setConsent (re-grant, no mint)", await consent.write.setConsent([requesterA.account.address, SCOPE_BOTH, 60n], as(user)));
  await record("revokeConsent", await consent.write.revokeConsent([requesterA.account.address], as(user)));
  await record("requestAccess (denied: REVOKED)", await dsm.write.requestAccess([addr], as(requesterA)));
  await record("requestAccess (denied: NO_CONSENT)", await dsm.write.requestAccess([addr], as(requesterB)));
  await record(
    "updateDocument",
    await registry.write.updateDocument([linkFor(addr), sha256(toHex(`${label}-front-v2`)), sha256(toHex(`${label}-back-v2`))], as(user)),
  );
  // 1-day consent to B, checked after the time jump below
  await consent.write.setConsent([requesterB.account.address, SCOPE_BOTH, 1n], as(user));
}

await testClient.increaseTime({ seconds: 86_400 + 1 });
await testClient.mine({ blocks: 1 });
for (const user of users) {
  await record("requestAccess (denied: EXPIRED)", await dsm.write.requestAccess([user.account.address], as(requesterB)));
}

// --- Report ---
const stats = Object.fromEntries(
  Object.entries(samples).map(([scenario, values]) => {
    const sum = values.reduce((a, b) => a + b, 0);
    return [scenario, { min: Math.min(...values), avg: Math.round(sum / values.length), max: Math.max(...values), count: values.length }];
  }),
);

console.log(`\nGas benchmark (logger: ${LOGGER}, ${USERS} users, gasUsed per transaction)\n`);
console.log("| Contract | Deployment gas | Bytecode size (bytes) |\n|---|---:|---:|");
for (const [name, d] of Object.entries(deployment)) console.log(`| ${name} | ${d.gas} | ${d.bytecodeSize} |`);
console.log("\n| Function (scenario) | Min | Avg | Max | Samples |\n|---|---:|---:|---:|---:|");
for (const [scenario, s] of Object.entries(stats)) console.log(`| ${scenario} | ${s.min} | ${s.avg} | ${s.max} | ${s.count} |`);

if (OUT) {
  writeFileSync(OUT, JSON.stringify({ logger: LOGGER, users: USERS, deployment, functions: stats }, null, 2) + "\n");
  console.log(`\nWrote ${OUT}`);
}
