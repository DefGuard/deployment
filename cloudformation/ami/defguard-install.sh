#!/usr/bin/env bash
set -e

echo "Updating apt repositories..."
apt update

echo "Installing dependencies..."
apt install -y ca-certificates curl awscli

echo "Adding Defguard GPG key..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://apt.defguard.net/defguard.asc -o /etc/apt/keyrings/defguard.asc
chmod a+r /etc/apt/keyrings/defguard.asc

echo "Adding Defguard repository..."
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/defguard.asc] https://apt.defguard.net/ trixie release " | \
   tee /etc/apt/sources.list.d/defguard.list > /dev/null

echo "Updating apt repositories after adding Defguard repo..."
apt update

echo "Installing Defguard packages with specific versions..."
echo "  defguard version: ${CORE_VERSION}"
echo "  defguard-proxy version: ${PROXY_VERSION}"
echo "  defguard-gateway version: ${GATEWAY_VERSION}"

apt install -y \
  defguard=${CORE_VERSION} \
  defguard-proxy=${PROXY_VERSION} \
  defguard-gateway=${GATEWAY_VERSION}

systemctl stop defguard
systemctl disable defguard
systemctl stop defguard-proxy
systemctl disable defguard-proxy
systemctl stop defguard-gateway
systemctl disable defguard-gateway
