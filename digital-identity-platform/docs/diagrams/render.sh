#!/usr/bin/env bash
# Re-renders every Mermaid diagram in this folder to PNG (for the report PDF)
# and SVG. Needs Node; mermaid-cli is fetched by npx on first use.
#   docs/diagrams/render.sh
# If Chrome isn't found, point PUPPETEER_EXECUTABLE_PATH at a Chrome/Chromium binary.
set -euo pipefail
cd "$(dirname "$0")"
for f in *.mmd; do
  b="${f%.mmd}"
  npx -y -p @mermaid-js/mermaid-cli@11 mmdc -c mermaid-config.json -i "$f" -o "$b.png" -s 3 -b white -q
  npx -y -p @mermaid-js/mermaid-cli@11 mmdc -c mermaid-config.json -i "$f" -o "$b.svg" -b white -q
  echo "rendered $b"
done
