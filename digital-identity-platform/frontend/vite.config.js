// Dev server for the front-end (`npm run frontend`). Besides serving the page,
// it answers GET /deployment.json with the deployed addresses (from Ignition)
// and the ABIs (from Hardhat's artifacts), read fresh on every request, so a
// redeploy only needs a page reload.
//
// AI-assisted: written with Claude Code (Claude Opus 5.5) on 2026-10-01; must be
// reviewed by the team and declared in the report's AI statement.
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { defineConfig } from "vite";

const projectRoot = resolve(import.meta.dirname, "..");
const addressesFile = resolve(projectRoot, "ignition/deployments/chain-31337/deployed_addresses.json");
const CONTRACTS = ["DigitalIdentityRegistry", "ConsentManager", "DataSharingManager", "AccessLogger", "AccessToken"];

function deploymentJson() {
  return {
    name: "deployment-json",
    configureServer(server) {
      server.middlewares.use("/deployment.json", (_req, res) => {
        res.setHeader("Content-Type", "application/json");
        if (!existsSync(addressesFile)) {
          res.statusCode = 404;
          res.end(JSON.stringify({ error: "Not deployed yet: run `npx hardhat node` and `npm run deploy:local`." }));
          return;
        }
        try {
          const addresses = JSON.parse(readFileSync(addressesFile, "utf8"));
          const contracts = Object.fromEntries(
            CONTRACTS.map((name) => {
              const artifact = resolve(projectRoot, `artifacts/contracts/${name}.sol/${name}.json`);
              return [name, { address: addresses[`DigitalIdentityPlatform#${name}`], abi: JSON.parse(readFileSync(artifact, "utf8")).abi }];
            }),
          );
          res.end(JSON.stringify(contracts));
        } catch (error) {
          res.statusCode = 500;
          res.end(JSON.stringify({ error: `Could not read the deployment: ${error.message}. Run \`npx hardhat compile\`.` }));
        }
      });
    },
  };
}

export default defineConfig({
  root: import.meta.dirname,
  plugins: [deploymentJson()],
  server: { host: "127.0.0.1", port: 5173, strictPort: true },
});
