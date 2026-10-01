#!/usr/bin/env bash
# Builds docs/report/report.pdf from report.md in the coursebook format:
# 10pt Times New Roman, double spaced, A4, 1-inch margins, numbered pages.
# Needs pandoc (3.x) and a TeX distribution with xelatex.
#   docs/report/build.sh
set -euo pipefail
cd "$(dirname "$0")"
pandoc report.md \
  --from markdown \
  --pdf-engine=xelatex \
  --resource-path=.:.. \
  --lua-filter=writer.lua \
  --include-in-header=header.tex \
  -V documentclass=article \
  -V fontsize=10pt \
  -V papersize=a4 \
  -V geometry:margin=1in \
  -V mainfont="Times New Roman" \
  -V monofont="Menlo" \
  -V colorlinks=true \
  -o report.pdf
echo "wrote $(pwd)/report.pdf"
