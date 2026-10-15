#!/usr/bin/env bash
# Install the pinned CI tools into $RUNNER_TEMP/bin and put that on PATH.
# Each download is checked against the sha256 pinned below, so a replaced
# release asset fails the job. No third-party setup action is involved.
# To bump a tool: change its version and hash together, from the release's
# own checksum file, and wait 14 days after the release before you do.
# Usage: scripts/ci/install-tools.sh terraform tflint trivy
set -euo pipefail

TERRAFORM_VERSION=1.16.4
TERRAFORM_SHA256=dc94af0eef1147718ad7c8daea792ed199e3e0492eec180d0adafa2a65a879df # terraform_1.16.4_linux_amd64.zip
TFLINT_VERSION=0.64.0
TFLINT_SHA256=cca9d13e2e1d7a2c627af60ff899a3c9b74212899416aeb96ec764d2ef954537 # tflint_linux_amd64.zip
TRIVY_VERSION=0.75.0
TRIVY_SHA256=c6e65abddb348e25f10549df887045629cf28cc72453cd1c63acb717316b3f3f # trivy_0.75.0_Linux-64bit.tar.gz

bin="${RUNNER_TEMP:?}/bin"
work="$(mktemp -d)"
mkdir -p "$bin"

fetch() { # url sha256 file
  curl -fsSL --retry 3 --proto '=https' --tlsv1.2 -o "$work/$3" "$1"
  echo "$2  $work/$3" | sha256sum --check --strict -
}

for tool in "$@"; do
  case "$tool" in
    terraform)
      fetch "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" "$TERRAFORM_SHA256" terraform.zip
      unzip -o -q "$work/terraform.zip" terraform -d "$bin"
      ;;
    tflint)
      fetch "https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}/tflint_linux_amd64.zip" "$TFLINT_SHA256" tflint.zip
      unzip -o -q "$work/tflint.zip" tflint -d "$bin"
      ;;
    trivy)
      fetch "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" "$TRIVY_SHA256" trivy.tar.gz
      tar -xzf "$work/trivy.tar.gz" -C "$bin" trivy
      ;;
    *)
      echo "unknown tool: $tool" >&2
      exit 2
      ;;
  esac
done

rm -rf "$work"
echo "$bin" >> "${GITHUB_PATH:?}"
