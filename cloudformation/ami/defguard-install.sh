#!/usr/bin/env bash
set -e

echo "Updating apt repositories..."
sudo apt update

echo "Installing dependencies..."
sudo apt install -y ca-certificates curl awscli

echo "Adding Defguard GPG key..."
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://apt.defguard.net/defguard.asc -o /etc/apt/keyrings/defguard.asc
sudo chmod a+r /etc/apt/keyrings/defguard.asc

echo "Adding Defguard repository..."
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/defguard.asc] https://apt.defguard.net/ trixie release " | \
   sudo tee /etc/apt/sources.list.d/defguard.list > /dev/null

echo "Updating apt repositories after adding Defguard repo..."
sudo apt update

echo "Installing Defguard packages with specific versions..."
echo "  defguard version: ${CORE_VERSION}"
echo "  defguard-proxy version: ${PROXY_VERSION}"
echo "  defguard-gateway version: ${GATEWAY_VERSION}"

sudo apt install -y \
  defguard=${CORE_VERSION} \
  defguard-proxy=${PROXY_VERSION} \
  defguard-gateway=${GATEWAY_VERSION}

sudo systemctl stop defguard
sudo systemctl disable defguard
sudo systemctl stop defguard-proxy
sudo systemctl disable defguard-proxy
sudo systemctl stop defguard-gateway
sudo systemctl disable defguard-gateway
