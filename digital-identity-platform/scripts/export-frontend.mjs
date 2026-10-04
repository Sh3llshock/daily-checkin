import fs from "node:fs";

const deployment = "ignition/deployments/chain-31337/deployed_addresses.json";
if (!fs.existsSync(deployment)) {
  console.error("No deployment found, run: npm run deploy:local");
  process.exit(1);
}

const addresses = JSON.parse(fs.readFileSync(deployment, "utf8"));
const names = ["AccessToken", "DigitalIdentity", "ConsentManager", "DataSharing"];

let out = "export const contracts = {\n";
for (const name of names) {
  const artifact = JSON.parse(fs.readFileSync(`artifacts/contracts/${name}.sol/${name}.json`, "utf8"));
  out += `  ${name}: { address: "${addresses["PlatformModule#" + name]}", abi: ${JSON.stringify(artifact.abi)} },\n`;
}
out += "};\n";

fs.writeFileSync("frontend/contracts.js", out);
console.log("Wrote frontend/contracts.js");
