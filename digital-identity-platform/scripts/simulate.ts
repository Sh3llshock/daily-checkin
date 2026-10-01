import { network } from "hardhat";
import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";
import { keccak256, sha256, toHex, parseEther } from "viem";
import fs from "node:fs";

// Simulates many patients and requesters using the platform and measures
// gas and confirmation time per operation.
//   npx hardhat node                                           (terminal 1)
//   npx hardhat run scripts/simulate.ts --network localhost    (terminal 2)
// SIM_SIZES=5,10 changes the number of patients per run.

const sizes = (process.env.SIM_SIZES ?? "5,10,20,50,100").split(",").map(Number);

type Stat = { gas: number[]; ms: number[] };

async function main() {
  const { viem, networkName } = await network.connect();
  const publicClient = await viem.getPublicClient();
  const testClient = await viem.getTestClient();
  const [admin] = await viem.getWalletClients();

  console.log(`\nSimulation on network: ${networkName}`);
  const allResults: any[] = [];

  for (const n of sizes) {
    const numRequesters = Math.max(1, Math.ceil(n / 5));
    console.log(`\n--- ${n} patients, ${numRequesters} requesters, 1 admin ---`);

    // fresh contracts for every run
    const token = await viem.deployContract("AccessToken");
    const identity = await viem.deployContract("DigitalIdentity");
    const consent = await viem.deployContract("ConsentManager", [identity.address, token.address]);
    const sharing = await viem.deployContract("DataSharing", [identity.address, consent.address]);
    await publicClient.waitForTransactionReceipt({ hash: await token.write.setMinter([consent.address]) });

    // new random accounts, funded with test ETH
    const patients = [];
    const requesters = [];
    for (let i = 0; i < n; i++) patients.push(privateKeyToAccount(generatePrivateKey()));
    for (let i = 0; i < numRequesters; i++) requesters.push(privateKeyToAccount(generatePrivateKey()));
    for (const acc of [...patients, ...requesters]) {
      await testClient.setBalance({ address: acc.address, value: parseEther("10") });
    }

    const stats: Record<string, Stat> = {};
    async function measure(name: string, send: () => Promise<`0x${string}`>) {
      const start = performance.now();
      const hash = await send();
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      const ms = performance.now() - start;
      if (!stats[name]) stats[name] = { gas: [], ms: [] };
      stats[name].gas.push(Number(receipt.gasUsed));
      stats[name].ms.push(ms);
    }

    const runStart = performance.now();

    for (const r of requesters) {
      await measure("approveRequester", () => identity.write.approveRequester([r.address]));
    }

    for (let i = 0; i < n; i++) {
      await measure("registerUser", () => identity.write.registerUser(
        [keccak256(toHex("email" + i)), "vault://p" + i, sha256(toHex("front" + i)), sha256(toHex("back" + i))],
        { account: patients[i] },
      ));
    }

    // every patient gives consent to one requester
    for (let i = 0; i < n; i++) {
      const r = requesters[i % numRequesters];
      await measure("grantConsent", () => consent.write.grantConsent([r.address, 2, 30n], { account: patients[i] }));
    }

    for (let i = 0; i < n; i++) {
      const r = requesters[i % numRequesters];
      await measure("requestAccess (1st, granted)", () => sharing.write.requestAccess([patients[i].address], { account: r }));
    }

    // half of the patients revoke
    for (let i = 0; i < n; i += 2) {
      const r = requesters[i % numRequesters];
      await measure("revokeConsent", () => consent.write.revokeConsent([r.address], { account: patients[i] }));
    }

    for (let i = 0; i < n; i++) {
      const r = requesters[i % numRequesters];
      const name = i % 2 === 0 ? "requestAccess (2nd, denied)" : "requestAccess (2nd, granted)";
      await measure(name, () => sharing.write.requestAccess([patients[i].address], { account: r }));
    }

    const runMs = performance.now() - runStart;

    // how long it takes to read the audit trail back from the events
    const evStart = performance.now();
    const granted = await publicClient.getContractEvents({ address: sharing.address, abi: sharing.abi, eventName: "AccessGranted", fromBlock: 0n });
    const denied = await publicClient.getContractEvents({ address: sharing.address, abi: sharing.abi, eventName: "AccessDenied", fromBlock: 0n });
    const eventMs = performance.now() - evStart;

    let txCount = 0;
    const ops: any[] = [];
    for (const [name, s] of Object.entries(stats)) {
      txCount += s.gas.length;
      const avgGas = Math.round(s.gas.reduce((a, b) => a + b, 0) / s.gas.length);
      const avgMs = s.ms.reduce((a, b) => a + b, 0) / s.ms.length;
      ops.push({ name, calls: s.gas.length, avgGas, avgMs: Number(avgMs.toFixed(2)) });
      console.log(`  ${name.padEnd(28)} calls=${String(s.gas.length).padStart(4)}  avg gas=${String(avgGas).padStart(7)}  avg time=${avgMs.toFixed(2)} ms`);
    }
    const totalGas = Object.values(stats).reduce((sum, s) => sum + s.gas.reduce((a, b) => a + b, 0), 0);
    console.log(`  total: ${txCount} tx, ${totalGas} gas, ${(runMs / 1000).toFixed(2)} s, ${(txCount / (runMs / 1000)).toFixed(1)} tx/s`);
    console.log(`  reading ${granted.length + denied.length} access events took ${eventMs.toFixed(1)} ms`);

    allResults.push({
      patients: n,
      requesters: numRequesters,
      transactions: txCount,
      totalGas,
      totalSeconds: Number((runMs / 1000).toFixed(2)),
      txPerSecond: Number((txCount / (runMs / 1000)).toFixed(1)),
      events: granted.length + denied.length,
      eventReadMs: Number(eventMs.toFixed(1)),
      operations: ops,
    });
  }

  fs.mkdirSync("results", { recursive: true });
  const file = `results/simulation-${networkName}.json`;
  fs.writeFileSync(file, JSON.stringify(allResults, null, 2));
  console.log(`\nSaved ${file}`);
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
