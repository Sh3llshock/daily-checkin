// Minimal front-end for the local Hardhat network (brief Step 6), using viem.
// Patient: register, grant and revoke consent, see your consents.
// Provider: request access, then fetch the files from the gatekeeper.
// Admin: whitelist requesters. Everyone: read any patient's access log.
//
// AI-assisted: written with Claude Code (Claude Opus 5.5) on 2026-10-01; must be
// reviewed by the team and declared in the report's AI statement.
import { createPublicClient, createWalletClient, formatEther, getAddress, http, parseEventLogs } from "viem";
import { mnemonicToAccount } from "viem/accounts";
import { hardhat } from "viem/chains";

// Same chain definition as the Lab 5 demo (frontend/lib/wagmi.ts).
const localHardhat = {
  ...hardhat,
  id: 31337,
  name: "Hardhat Local",
  rpcUrls: { default: { http: ["http://127.0.0.1:8545"] } },
};

// The public test mnemonic of every `npx hardhat node`. These keys only hold
// ETH on a local development chain; never use them anywhere else.
const MNEMONIC = "test test test test test test test test test test test junk";
const ACCOUNT_ROLES = ["Admin (deployer)", "Patient (demo)", "Provider (demo)"];
const ACCOUNTS = Array.from({ length: 10 }, (_, i) => ({
  index: i,
  account: mnemonicToAccount(MNEMONIC, { addressIndex: i }),
  role: ACCOUNT_ROLES[i] ?? "Test account",
}));

// Match ConsentManager.Scope and AccessLogger.Outcome / Reason.
const SCOPES = ["Front only", "Back only", "Both sides"];
const OUTCOMES = ["DENIED", "GRANTED"];
const REASONS = ["", "NO_CONSENT", "REVOKED", "EXPIRED"];

const publicClient = createPublicClient({ chain: localHardhat, transport: http() });
let contracts = {};
let me = ACCOUNTS[0];
let lastGranted = null; // { user, txHash } of the provider's latest GRANTED request

// --- small helpers -----------------------------------------------------------

const $ = (id) => document.getElementById(id);

function h(tag, attrs = {}, ...children) {
  const el = document.createElement(tag);
  for (const [key, value] of Object.entries(attrs)) {
    if (key.startsWith("on")) el.addEventListener(key.slice(2), value);
    else if (value !== false && value != null) el.setAttribute(key, value === true ? "" : value);
  }
  for (const child of children.flat()) el.append(child instanceof Node ? child : String(child));
  return el;
}

function labelFor(address) {
  const known = ACCOUNTS.find((a) => a.account.address.toLowerCase() === address.toLowerCase());
  return known ? `#${known.index} ${known.role}` : `${address.slice(0, 6)}…${address.slice(-4)}`;
}

function addressCell(address) {
  return h("span", { title: address }, h("code", {}, `${address.slice(0, 6)}…${address.slice(-4)}`), " ", h("span", { class: "muted" }, labelFor(address)));
}

function formatTime(seconds) {
  return new Date(Number(seconds) * 1000).toISOString().replace("T", " ").slice(0, 16) + " UTC";
}

// Success messages fade after 5 s; errors stay until dismissed (they often
// carry a command to run).
let toastTimer;
function toast(message, kind = "ok") {
  if (kind === "error") {
    $("alert").hidden = false;
    $("alert-text").textContent = message;
    return;
  }
  $("toast").textContent = message;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => ($("toast").textContent = ""), 5000);
}
$("alert-close").addEventListener("click", () => {
  $("alert").hidden = true;
  $("alert-text").textContent = "";
});

function errorText(error) {
  return error?.shortMessage || error?.details || error?.message || String(error);
}

async function sha256Hex(bytes) {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  return "0x" + Array.from(digest, (b) => b.toString(16).padStart(2, "0")).join("");
}

// Same normalisation as offchain/hash_tool.py: email_hash().
const emailHash = (email) => sha256Hex(new TextEncoder().encode(email.trim().toLowerCase()));

// Same text as offchain/gatekeeper.py: access_message().
const accessMessage = (user, txHash) =>
  `Digital Identity Platform: gatekeeper file request\nuser: ${getAddress(user)}\ntx: ${txHash.toLowerCase()}`;

// --- chain access ------------------------------------------------------------

const read = (name, functionName, args = []) =>
  publicClient.readContract({ address: contracts[name].address, abi: contracts[name].abi, functionName, args });

const events = (name, eventName, args) =>
  publicClient.getContractEvents({ address: contracts[name].address, abi: contracts[name].abi, eventName, args, fromBlock: 0n });

async function write(name, functionName, args, label) {
  const wallet = createWalletClient({ account: me.account, chain: localHardhat, transport: http() });
  const hash = await wallet.writeContract({ address: contracts[name].address, abi: contracts[name].abi, functionName, args });
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  if (receipt.status !== "success") throw new Error(`${label} reverted`);
  toast(`${label}: done (${receipt.gasUsed.toLocaleString()} gas)`, "ok");
  return receipt;
}

async function chainNow() {
  return (await publicClient.getBlock()).timestamp;
}

async function registeredUsers() {
  const logs = await events("DigitalIdentityRegistry", "UserRegistered");
  return [...new Set(logs.map((l) => l.args.user))];
}

async function requesters() {
  const logs = await events("DigitalIdentityRegistry", "RequesterStatusChanged");
  const addresses = [...new Set(logs.map((l) => l.args.requester))];
  return Promise.all(addresses.map(async (a) => ({ address: a, approved: await read("DigitalIdentityRegistry", "isApprovedRequester", [a]) })));
}

function fillSelect(select, addresses, emptyText) {
  const previous = select.value;
  select.replaceChildren(
    ...(addresses.length ? addresses.map((a) => h("option", { value: a }, `${labelFor(a)} — ${a}`)) : [h("option", { value: "" }, emptyText)]),
  );
  if (addresses.includes(previous)) select.value = previous;
}

// --- rendering ---------------------------------------------------------------

async function renderStatus() {
  const address = me.account.address;
  const [eth, act, registered, approved, owner] = await Promise.all([
    publicClient.getBalance({ address }),
    read("AccessToken", "balanceOf", [address]),
    read("DigitalIdentityRegistry", "isRegistered", [address]),
    read("DigitalIdentityRegistry", "isApprovedRequester", [address]),
    read("DigitalIdentityRegistry", "owner"),
  ]);
  const item = (term, value) => [h("div", {}, h("dt", {}, term), h("dd", {}, value))];
  const isAdmin = owner === address;
  for (const button of $("whitelist-form").querySelectorAll("button")) button.disabled = !isAdmin;
  $("admin-hint").textContent = isAdmin
    ? "You are the admin. The admin can't see files, grant consent or edit logs."
    : "Only the admin (account #0) can change the whitelist: switch accounts to use these buttons.";
  $("status").replaceChildren(
    ...item("Address", h("code", {}, address)),
    ...item("ETH", Number(formatEther(eth)).toFixed(3)),
    ...item("ACT reward", formatEther(act)),
    ...item("Roles", [registered && "registered patient", approved && "whitelisted provider", isAdmin && "admin"].filter(Boolean).join(", ") || "none yet"),
  );
}

async function renderIdentity() {
  const address = me.account.address;
  const [emailHashOnChain, link, front, back, registered] = await read("DigitalIdentityRegistry", "getUserRecord", [address]);
  $("register-form").hidden = registered;
  $("fake-data-cmd").textContent = `python offchain/fake_data.py ${address}`;
  if (!registered) {
    $("identity").replaceChildren(h("p", {}, "Not registered yet."));
    return;
  }
  const row = (term, value) => h("tr", {}, h("th", { scope: "row" }, term), h("td", {}, h("code", { class: "wrap" }, value)));
  $("identity").replaceChildren(
    h("p", {}, "Registered. This is everything the chain stores about you, and anyone can read it:"),
    h("table", { class: "kv" }, h("tbody", {}, row("Email hash", emailHashOnChain), row("Document link", link), row("Front hash", front), row("Back hash", back))),
  );
}

async function renderConsentForm() {
  const approved = (await requesters()).filter((r) => r.approved).map((r) => r.address);
  fillSelect($("consent-requester"), approved, "No whitelisted providers yet");
}

async function renderConsents() {
  const user = me.account.address;
  const granted = await events("ConsentManager", "ConsentGranted", { user });
  const asked = [...new Set(granted.map((l) => l.args.requester))];
  if (!asked.length) {
    $("consents").replaceChildren(h("p", { class: "muted" }, "You haven't granted any consent."));
    return;
  }
  const now = await chainNow();
  const rows = await Promise.all(
    asked.map(async (requester) => {
      const [scope, grantedAt, expiresAt, revoked] = await read("ConsentManager", "getConsent", [user, requester]);
      const state = revoked ? "Revoked" : now > expiresAt ? "Expired" : "Active";
      const action =
        state === "Active"
          ? h(
              "button",
              {
                type: "button",
                class: "secondary small",
                "aria-label": `Revoke consent for ${labelFor(requester)}`,
                onclick: (event) => run(() => write("ConsentManager", "revokeConsent", [requester], "Revoke consent"), event.currentTarget),
              },
              "Revoke",
            )
          : "";
      return h(
        "tr",
        {},
        h("td", {}, addressCell(requester)),
        h("td", {}, SCOPES[scope]),
        h("td", {}, formatTime(grantedAt)),
        h("td", {}, formatTime(expiresAt)),
        h("td", {}, h("span", { class: `badge ${state.toLowerCase()}` }, state)),
        h("td", {}, action),
      );
    }),
  );
  $("consents").replaceChildren(
    h(
      "table",
      {},
      h("thead", {}, h("tr", {}, ...["Provider", "Scope", "Granted", "Expires", "State", ""].map((t) => h("th", { scope: "col" }, t)))),
      h("tbody", {}, rows),
    ),
  );
}

async function renderPatientsLists() {
  const users = await registeredUsers();
  fillSelect($("request-user"), users, "No registered patients yet");
  fillSelect($("log-user"), users, "No registered patients yet");
}

async function renderRequesters() {
  const list = await requesters();
  $("known-accounts").replaceChildren(...ACCOUNTS.map((a) => h("option", { value: a.account.address }, `#${a.index} ${a.role}`)));
  if (!list.length) {
    $("requesters").replaceChildren(h("p", { class: "muted" }, "Nobody has been whitelisted yet."));
    return;
  }
  $("requesters").replaceChildren(
    h(
      "table",
      {},
      h("thead", {}, h("tr", {}, h("th", { scope: "col" }, "Requester"), h("th", { scope: "col" }, "Status"))),
      h("tbody", {}, list.map((r) => h("tr", {}, h("td", {}, addressCell(r.address)), h("td", {}, h("span", { class: `badge ${r.approved ? "active" : "revoked"}` }, r.approved ? "Whitelisted" : "Removed"))))),
    ),
  );
}

async function renderLog() {
  const user = $("log-user").value;
  if (!user) {
    $("log-entries").replaceChildren();
    return;
  }
  const entries = await read("AccessLogger", "getLogs", [user]);
  if (!entries.length) {
    $("log-entries").replaceChildren(h("p", { class: "muted" }, "No access attempts yet."));
    return;
  }
  $("log-entries").replaceChildren(
    h(
      "table",
      {},
      h("thead", {}, h("tr", {}, ...["#", "When", "Requester", "Outcome", "Reason"].map((t) => h("th", { scope: "col" }, t)))),
      h(
        "tbody",
        {},
        entries.map((e, i) =>
          h(
            "tr",
            {},
            h("td", {}, i + 1),
            h("td", {}, formatTime(e.timestamp)),
            h("td", {}, addressCell(e.requester)),
            h("td", {}, h("span", { class: `badge ${OUTCOMES[e.outcome] === "GRANTED" ? "active" : "revoked"}` }, OUTCOMES[e.outcome])),
            h("td", {}, REASONS[e.reason]),
          ),
        ),
      ),
    ),
  );
}

async function refresh() {
  await Promise.all([renderStatus(), renderIdentity(), renderConsentForm(), renderConsents(), renderPatientsLists(), renderRequesters()]);
  await renderLog();
}

// Runs one user action. The button that started it is disabled meanwhile, so
// a double click can't send the same transaction twice.
async function run(action, button) {
  if (button) {
    button.disabled = true;
    button.setAttribute("aria-busy", "true");
  }
  try {
    await action();
  } catch (error) {
    toast(errorText(error), "error");
  } finally {
    if (button) {
      button.disabled = false;
      button.removeAttribute("aria-busy");
    }
  }
  await refresh().catch((error) => toast(errorText(error), "error"));
}

// --- actions -----------------------------------------------------------------

$("register-form").addEventListener("submit", (event) => {
  event.preventDefault();
  run(async () => {
    const [front, back] = await Promise.all([$("front-file").files[0].arrayBuffer(), $("back-file").files[0].arrayBuffer()]);
    const address = me.account.address;
    const link = `${$("gatekeeper-url").value.replace(/\/$/, "")}/users/${address}`;
    const args = [await emailHash($("email").value), link, await sha256Hex(front), await sha256Hex(back)];
    await write("DigitalIdentityRegistry", "registerUser", args, "Register");
  }, event.submitter);
});

$("consent-form").addEventListener("submit", (event) => {
  event.preventDefault();
  run(
    () => write("ConsentManager", "setConsent", [$("consent-requester").value, Number($("consent-scope").value), BigInt($("consent-days").value)], "Grant consent"),
    event.submitter,
  );
});

$("request-form").addEventListener("submit", (event) => {
  event.preventDefault();
  run(async () => {
    const user = $("request-user").value;
    const receipt = await write("DataSharingManager", "requestAccess", [user], "Request access");
    const decoded = parseEventLogs({ abi: contracts.DataSharingManager.abi, logs: receipt.logs });
    const granted = decoded.find((e) => e.eventName === "AccessGranted");
    const denied = decoded.find((e) => e.eventName === "AccessDenied");
    lastGranted = granted ? { user, txHash: receipt.transactionHash } : null;
    $("request-result").hidden = false;
    $("fetch-btn").hidden = !granted;
    $("files").replaceChildren();
    $("request-outcome").replaceChildren(
      h(
        "p",
        {},
        h("span", { class: `badge ${granted ? "active" : "revoked"}` }, granted ? "GRANTED" : `DENIED: ${REASONS[denied.args.reason]}`),
        " ",
        granted ? "Logged. Show this transaction to the gatekeeper to get the files." : "Logged. No data released.",
      ),
      h("p", { class: "muted" }, "Transaction ", h("code", { class: "wrap" }, receipt.transactionHash)),
    );
  }, event.submitter);
});

$("fetch-btn").addEventListener("click", (event) =>
  run(async () => {
    const { user, txHash } = lastGranted;
    const [, link, frontHash, backHash] = await read("DigitalIdentityRegistry", "getUserRecord", [user]);
    const signature = await me.account.signMessage({ message: accessMessage(user, txHash) });
    let response;
    try {
      response = await fetch(`${link}/files`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ tx_hash: txHash, signature }) });
    } catch {
      throw new Error(`Can't reach the gatekeeper at ${link}. Start it with: python offchain/gatekeeper.py`);
    }
    const body = await response.json();
    if (!response.ok) throw new Error(`Gatekeeper refused: ${body.error} (${body.detail})`);
    const expected = { "id_front.json": frontHash, "id_back.json": backHash };
    const cards = await Promise.all(
      Object.entries(body.files).map(async ([name, b64]) => {
        const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
        const matches = (await sha256Hex(bytes)) === expected[name];
        return h(
          "div",
          { class: "file" },
          h("p", {}, h("strong", {}, name), " ", h("span", { class: `badge ${matches ? "active" : "revoked"}` }, matches ? "hash matches the chain" : "HASH MISMATCH")),
          h("pre", {}, new TextDecoder().decode(bytes)),
        );
      }),
    );
    $("files").replaceChildren(h("p", {}, `Scope ${body.scope}: the gatekeeper released ${Object.keys(body.files).length} file(s).`), ...cards);
    $("fetch-btn").hidden = true; // each GRANTED transaction releases the files once
    toast("Files received and checked against the on-chain hashes", "ok");
  }, event.currentTarget),
);

$("whitelist-form").addEventListener("submit", (event) => {
  event.preventDefault();
  const approve = event.submitter?.dataset.approve === "true";
  run(
    () => write("DigitalIdentityRegistry", "setRequesterStatus", [$("whitelist-address").value, approve], approve ? "Approve requester" : "Remove requester"),
    event.submitter,
  );
});

$("log-form").addEventListener("submit", (event) => {
  event.preventDefault();
  renderLog().catch((error) => toast(errorText(error), "error"));
});
$("log-user").addEventListener("change", () => renderLog().catch((error) => toast(errorText(error), "error")));

// Tabs follow the ARIA tablist pattern: one tab in the Tab order, arrow keys,
// Home and End move between them.
const tabs = [...document.querySelectorAll('[role="tab"]')];
function selectTab(tab) {
  for (const other of tabs) {
    const selected = other === tab;
    other.setAttribute("aria-selected", String(selected));
    other.tabIndex = selected ? 0 : -1;
    $(other.getAttribute("aria-controls")).hidden = !selected;
  }
}
for (const tab of tabs) {
  tab.addEventListener("click", () => selectTab(tab));
  tab.addEventListener("keydown", (event) => {
    const i = tabs.indexOf(tab);
    const next = { ArrowRight: tabs[(i + 1) % tabs.length], ArrowLeft: tabs[(i - 1 + tabs.length) % tabs.length], Home: tabs[0], End: tabs.at(-1) }[event.key];
    if (!next) return;
    event.preventDefault();
    selectTab(next);
    next.focus();
  });
}

$("account").addEventListener("change", (event) => {
  me = ACCOUNTS[Number(event.target.value)];
  lastGranted = null;
  $("request-result").hidden = true;
  run(async () => {});
});

// --- start -------------------------------------------------------------------

async function start() {
  $("account").replaceChildren(...ACCOUNTS.map((a) => h("option", { value: a.index }, `#${a.index} ${a.role} — ${a.account.address}`)));
  const response = await fetch("/deployment.json");
  const body = await response.json();
  if (!response.ok) throw new Error(body.error);
  contracts = body;
  const code = await publicClient.getCode({ address: contracts.DigitalIdentityRegistry.address }).catch(() => {
    throw new Error("Can't reach the node at http://127.0.0.1:8545. Start it with `npx hardhat node`.");
  });
  if (!code) throw new Error("No contracts at the deployed addresses: run `npm run deploy:local -- --reset`.");
  await refresh();
}

start().catch((error) => {
  $("status").replaceChildren(h("div", {}, h("dt", {}, "Not connected"), h("dd", {}, errorText(error))));
  toast(errorText(error), "error");
});
