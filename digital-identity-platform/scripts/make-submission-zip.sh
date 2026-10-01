#!/usr/bin/env bash
# Builds the Canvas submission zip (TASKS D0.2): the documented code, docs,
# results and the report PDF, i.e. everything git tracks or would track, without
# node_modules, build output, virtualenvs or simulation scratch data.
# Rebuild it after the report is final:
#   digital-identity-platform/scripts/make-submission-zip.sh
# Output: digital-identity-platform/dist/digital-identity-platform.zip (dist/ is gitignored)
#
# AI-assisted: written with Claude Code (Claude Opus 5.5) on 2026-10-01; must be
# reviewed by the team and declared in the report's AI statement.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -f docs/report/report.pdf ]; then
  echo "warning: docs/report/report.pdf is missing; run docs/report/build.sh first" >&2
fi

mkdir -p dist
out="dist/digital-identity-platform.zip"
rm -f "$out"
# Files git tracks plus new files it would track (respects .gitignore).
git ls-files --cached --others --exclude-standard -- . ':!dist' | zip -q -@ "$out"
echo "wrote $(pwd)/$out ($(du -h "$out" | cut -f1), $(unzip -Z1 "$out" | wc -l | tr -d ' ') files)"
