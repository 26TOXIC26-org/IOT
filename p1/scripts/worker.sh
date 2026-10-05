#!/bin/bash
set -e

echo "=== Updating packages ==="
apt-get update

echo "=== Installing dependencies ==="
apt-get install -y curl

echo "=== Waiting for K3s token ==="
until [ -f /vagrant/k3s-token ]; do
    sleep 2
done

echo "=== Reading K3s token ==="
K3S_TOKEN=$(cat /vagrant/k3s-token)

echo "=== Installing K3s Agent ==="
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="agent --node-ip=192.168.56.111" K3S_URL=https://192.168.56.110:6443 K3S_TOKEN="$K3S_TOKEN" sh -

echo "=== K3s Agent installed ==="

echo "=== K3s service status ==="
systemctl status k3s-agent --no-pager