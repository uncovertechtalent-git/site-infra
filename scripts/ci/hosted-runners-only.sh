#!/usr/bin/env bash
# Fail when a workflow asks for anything but a GitHub-hosted runner. This
# repository is public: a self-hosted runner reachable from it would run code
# from pull requests (ADR-0001). The enterprise runner of ADR-0002 gets its
# own, reviewed exception here when it exists.
set -euo pipefail
bad=$(grep -nE '^\s*runs-on:' .github/workflows/*.yml \
  | grep -vE 'runs-on:\s*(ubuntu|windows|macos)-[0-9a-z.-]+\s*(#.*)?$' || true)
if [ -n "$bad" ]; then
  echo "::error::runs-on must name a GitHub-hosted runner label:"
  echo "$bad"
  exit 1
fi
echo "every job runs on a GitHub-hosted runner"
