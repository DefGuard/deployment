#!/bin/bash
set -euo pipefail

TAG="2.0.0-alpha2"
ISO_PATH="${PWD}/ubuntu-24.04.4-live-server-amd64.iso"

if [ ! -f "$ISO_PATH" ]; then
  echo "Missing ISO: $ISO_PATH" >&2
  echo "Download it first with:" >&2
  echo "  curl -fL -o ubuntu-24.04.4-live-server-amd64.iso https://releases.ubuntu.com/24.04.4/ubuntu-24.04.4-live-server-amd64.iso" >&2
  exit 1
fi

packer init defguard.pkr.hcl

packer build \
  -var "iso_url=file://$ISO_PATH" \
  -var "core_tag=$TAG" \
  -var "proxy_tag=$TAG" \
  -var "gateway_tag=$TAG" \
  defguard.pkr.hcl
