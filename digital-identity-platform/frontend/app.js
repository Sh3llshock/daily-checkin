import {
  createPublicClient, createWalletClient, http, parseEventLogs,
  keccak256, encodePacked, formatEther, toHex,
} from "https://esm.sh/viem@2.57.1";
import { privateKeyToAccount } from "https://esm.sh/viem@2.57.1/accounts";
import { hardhat } from "https://esm.sh/viem@2.57.1/chains";
import { contracts } from "./contracts.js";

const RPC = "http://127.0.0.1:8545";

// Default hardhat node accounts. The keys are public test keys and only
// work on the local chain. The labels are just to make the demo easier.
const ACCOUNTS = [
  ["Admin", "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"],
  ["Patient 1", "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"],
  ["Doctor", "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a"],
  ["Stranger", "0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6"],
  ["Patient 2", "0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a"],
  ["Lab", "0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba"],
].map(([label, key]) => ({ label, account: privateKeyToAccount(key) }));

const SCOPES = ["Front only", "Back only", "Front and back"];
const REASONS = ["-", "Requester not approved", "No consent", "Consent revoked", "Consent expired"];

const publicClient = createPublicClient({ chain: hardhat, transport: http(RPC) });
let current = ACCOUNTS[0];
let wallet = null;

const $ = (id) => document.getElementById(id);

// ---------- helpers ----------

function nameOf(address) {
  const found = ACCOUNTS.find((a) => a.account.address.toLowerCase() === address.toLowerCase());
  return found ? `${found.label} (${short(address)})` : short(address);
}

function short(address) {
  return address.slice(0, 6) + "..." + address.slice(-4);
}

function date(timestamp) {
  return new Date(Number(timestamp) * 1000).toLocaleString();
}

function setStatus(text, isError = false) {
  $("status").textContent = text;
  $("status").style.color = isError ? "#c62828" : "#1f4e79";
}

function read(name, functionName, args = []) {
  return publicClient.readContract({ ...contracts[name], functionName, args });
}

function events(name, eventName, args) {
  return publicClient.getContractEvents({ ...contracts[name], eventName, args, fromBlock: 0n });
}

// sends a transaction from the selected account and waits for it
async function write(name, functionName, args) {
  setStatus(`Sending ${functionName}...`);
  try {
    const hash = await wallet.writeContract({ ...contracts[name], functionName, args });
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    setStatus(`${functionName} confirmed in block ${receipt.blockNumber} (gas used ${receipt.gasUsed})`);
    return receipt;
  } catch (err) {
    // show the revert message from require(), e.g. "Duration must be 1-365 days"
    setStatus(err.shortMessage ?? err.message, true);
    return null;
  }
}

async function sha256File(file) {
  const buffer = await file.arrayBuffer();
  const digest = await crypto.subtle.digest("SHA-256", buffer);
  return toHex(new Uint8Array(digest));
}

function fillTable(table, headers, rows) {
  if (rows.length === 0) {
    table.innerHTML = `<tr><td class="hint">Nothing yet</td></tr>`;
    return;
  }
  let html = "<tr>" + headers.map((h) => `<th>${h}</th>`).join("") + "</tr>";
  for (const row of rows) {
    html += "<tr>" + row.map((c) => `<td>${c}</td>`).join("") + "</tr>";
  }
  table.innerHTML = html;
}

async function approvedRequesters() {
  const approved = await events("DigitalIdentity", "RequesterApproved");
  const list = [...new Set(approved.map((e) => e.args.requester))];
  const result = [];
  for (const r of list) {
    if (await read("DigitalIdentity", "isApprovedRequester", [r])) result.push(r);
  }
  return result;
}

async function registeredPatients() {
  const registered = await events("DigitalIdentity", "UserRegistered");
  return registered.map((e) => e.args.user);
}

function fillSelect(select, addresses) {
  const old = select.value;
  select.innerHTML = addresses.map((a) => `<option value="${a}">${nameOf(a)}</option>`).join("");
  if (addresses.includes(old)) select.value = old;
}

// ---------- account ----------

function selectAccount(index) {
  current = ACCOUNTS[index];
  wallet = createWalletClient({ account: current.account, chain: hardhat, transport: http(RPC) });
  $("saltBox").textContent = "";
  $("requestResult").textContent = "";
  $("updRef").value = "";
  refresh();
}

async function refreshAccountInfo() {
  const balance = await read("AccessToken", "balanceOf", [current.account.address]);
  $("accountInfo").textContent = `${current.account.address}  |  ${formatEther(balance)} ACT`;
}

// ---------- patient tab ----------

async function refreshPatient() {
  const me = current.account.address;
  const registered = await read("DigitalIdentity", "isRegistered", [me]);
  $("registerCard").style.display = registered ? "none" : "block";
  $("updateCard").style.display = registered ? "block" : "none";

  if (registered) {
    const [emailHash, frontHash, backHash, ref, registeredAt] = await read("DigitalIdentity", "getUser", [me]);
    if (!$("updRef").value) $("updRef").value = ref;
    fillTable($("identityTable"), ["Field", "Value"], [
      ["Email hash", emailHash],
      ["Front photo hash", frontHash],
      ["Back photo hash", backHash],
      ["Storage reference", ref],
      ["Registered", date(registeredAt)],
    ]);
  } else {
    fillTable($("identityTable"), [], []);
  }

  fillSelect($("grantRequester"), await approvedRequesters());

  // consents = every requester this patient ever granted, with the current state
  const granted = await events("ConsentManager", "ConsentGranted", { patient: me });
  const requesters = [...new Set(granted.map((e) => e.args.requester))];
  const now = (await publicClient.getBlock()).timestamp;
  const rows = [];
  for (const r of requesters) {
    const [scope, , expiresAt, revoked] = await read("ConsentManager", "getConsent", [me, r]);
    let state = "Active";
    if (revoked) state = "Revoked";
    else if (now >= expiresAt) state = "Expired";
    const button = state === "Active" ? `<button class="small" data-revoke="${r}">Revoke</button>` : "";
    rows.push([nameOf(r), SCOPES[scope], date(expiresAt), state, button]);
  }
  fillTable($("consentTable"), ["Requester", "Scope", "Valid until", "State", ""], rows);
}

async function register() {
  const email = $("regEmail").value.trim().toLowerCase();
  const ref = $("regRef").value.trim();
  const front = $("regFront").files[0];
  const back = $("regBack").files[0];
  if (!email || !ref || !front || !back) {
    setStatus("Fill in all fields and choose both photos", true);
    return;
  }

  // the salt makes the email hash impossible to guess, the patient has to keep it
  const salt = toHex(crypto.getRandomValues(new Uint8Array(32)));
  const emailHash = keccak256(encodePacked(["bytes32", "string"], [salt, email]));
  const frontHash = await sha256File(front);
  const backHash = await sha256File(back);

  const receipt = await write("DigitalIdentity", "registerUser", [emailHash, ref, frontHash, backHash]);
  if (receipt) {
    $("saltBox").textContent = "Save your salt, you need it to prove your email later: " + salt;
    refresh();
  }
}

// new photos after the ID was renewed, hashed in the browser like at registration
async function updateDocument() {
  const ref = $("updRef").value.trim();
  const front = $("updFront").files[0];
  const back = $("updBack").files[0];
  if (!ref || !front || !back) {
    setStatus("Fill in the storage reference and choose both new photos", true);
    return;
  }

  const frontHash = await sha256File(front);
  const backHash = await sha256File(back);
  if (await write("DigitalIdentity", "updateDocument", [ref, frontHash, backHash])) {
    $("updFront").value = "";
    $("updBack").value = "";
    refresh();
  }
}

async function grant() {
  const requester = $("grantRequester").value;
  if (!requester) {
    setStatus("No approved requester to choose", true);
    return;
  }
  const scope = Number($("grantScope").value);
  const days = BigInt($("grantDays").value || 0);
  if (await write("ConsentManager", "grantConsent", [requester, scope, days])) refresh();
}

async function revoke(requester) {
  if (await write("ConsentManager", "revokeConsent", [requester])) refresh();
}

// ---------- requester tab ----------

async function refreshRequester() {
  fillSelect($("requestPatient"), await registeredPatients());

  const me = current.account.address;
  const granted = await events("DataSharing", "AccessGranted", { requester: me });
  const denied = await events("DataSharing", "AccessDenied", { requester: me });
  const all = [
    ...granted.map((e) => ({ e, ok: true })),
    ...denied.map((e) => ({ e, ok: false })),
  ].sort((a, b) => Number(b.e.blockNumber - a.e.blockNumber));

  fillTable($("myRequestsTable"), ["Block", "Patient", "Result", "Details"], all.map(({ e, ok }) => [
    e.blockNumber.toString(),
    nameOf(e.args.patient),
    ok ? `<span class="granted">GRANTED</span>` : `<span class="denied">DENIED</span>`,
    ok ? SCOPES[e.args.scope] : REASONS[e.args.reason],
  ]));
}

async function requestAccess() {
  const patient = $("requestPatient").value;
  if (!patient) {
    setStatus("No registered patient to choose", true);
    return;
  }
  const receipt = await write("DataSharing", "requestAccess", [patient]);
  if (!receipt) return;

  const logs = parseEventLogs({ abi: contracts.DataSharing.abi, logs: receipt.logs });
  const log = logs[0];
  if (log.eventName === "AccessGranted") {
    $("requestResult").innerHTML = `<span class="granted">GRANTED</span> (${SCOPES[log.args.scope]}).
      Show this transaction to the patient's vault to get the files:<br><code>${receipt.transactionHash}</code>`;
  } else {
    $("requestResult").innerHTML = `<span class="denied">DENIED</span>: ${REASONS[log.args.reason]}. The attempt was logged.`;
  }
  refresh();
}

// ---------- admin tab ----------

async function refreshAdmin() {
  const requesters = await approvedRequesters();
  fillTable($("requesterTable"), ["Requester", ""], requesters.map((r) => [
    nameOf(r),
    `<button class="small" data-remove="${r}">Remove</button>`,
  ]));
  const paused = await read("DataSharing", "paused");
  $("pausedState").textContent = paused ? "PAUSED" : "running";
  $("rewardAmount").textContent = formatEther(await read("ConsentManager", "rewardAmount"));
}

async function approve() {
  const address = $("approveAddress").value.trim();
  if (await write("DigitalIdentity", "approveRequester", [address])) {
    $("approveAddress").value = "";
    refresh();
  }
}

// ---------- audit tab ----------

async function refreshAudit() {
  fillSelect($("auditPatient"), await registeredPatients());
  const patient = $("auditPatient").value;
  if (!patient) {
    fillTable($("auditTable"), [], []);
    return;
  }
  const logs = await read("DataSharing", "getLogs", [patient]);
  fillTable($("auditTable"), ["#", "Time", "Requester", "Result", "Details"], logs.map((l, i) => [
    i,
    date(l.timestamp),
    nameOf(l.requester),
    l.result === 0 ? `<span class="granted">GRANTED</span>` : `<span class="denied">DENIED</span>`,
    l.result === 0 ? SCOPES[l.scope] : REASONS[l.reason],
  ]).reverse());
}

// ---------- setup ----------

async function refresh() {
  try {
    await refreshAccountInfo();
    await Promise.all([refreshPatient(), refreshRequester(), refreshAdmin(), refreshAudit()]);
  } catch (err) {
    setStatus("Cannot reach the contracts. Is `npx hardhat node` running and deployed? " + (err.shortMessage ?? err.message), true);
  }
}

function showTab(name) {
  document.querySelectorAll("nav button").forEach((b) => b.classList.toggle("active", b.dataset.tab === name));
  document.querySelectorAll(".tab").forEach((t) => t.classList.toggle("hidden", t.id !== "tab-" + name));
}

$("accountSelect").innerHTML = ACCOUNTS.map((a, i) =>
  `<option value="${i}">${a.label} - ${short(a.account.address)}</option>`).join("");
$("accountSelect").addEventListener("change", (e) => selectAccount(Number(e.target.value)));
document.querySelectorAll("nav button").forEach((b) => b.addEventListener("click", () => showTab(b.dataset.tab)));

$("registerBtn").addEventListener("click", register);
$("updateBtn").addEventListener("click", updateDocument);
$("grantBtn").addEventListener("click", grant);
$("requestBtn").addEventListener("click", requestAccess);
$("approveBtn").addEventListener("click", approve);
$("pauseBtn").addEventListener("click", async () => { if (await write("DataSharing", "pause", [])) refresh(); });
$("unpauseBtn").addEventListener("click", async () => { if (await write("DataSharing", "unpause", [])) refresh(); });
$("auditPatient").addEventListener("change", refreshAudit);

// buttons inside tables
document.addEventListener("click", async (e) => {
  if (e.target.dataset.revoke) revoke(e.target.dataset.revoke);
  if (e.target.dataset.remove) {
    if (await write("DigitalIdentity", "removeRequester", [e.target.dataset.remove])) refresh();
  }
});

// ?account=1#requester opens a certain account and tab (handy for screenshots)
const params = new URLSearchParams(location.search);
const startAccount = Number(params.get("account") ?? 0);
$("accountSelect").value = startAccount;
showTab(location.hash.slice(1) || "patient");
selectAccount(startAccount);
