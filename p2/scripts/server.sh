#!/bin/bash
set -e

echo "=== Updating packages ==="
apt-get update

echo "=== Installing dependencies ==="
apt-get install -y curl

echo "=== Installing K3s Server ==="
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --node-ip=192.168.56.110" sh -

echo "=== Configuring kubectl permissions ==="
chmod 644 /etc/rancher/k3s/k3s.yaml

echo "=== Waiting for K3s node ==="
until kubectl get nodes >/dev/null 2>&1; do
    sleep 2
done
echo "=== Configuring kubectl alias ==="
grep -qxF 'alias k=kubectl' /home/vagrant/.bashrc || echo 'alias k=kubectl' >> /home/vagrant/.bashrc
echo "=== K3s node is ready ==="
echo "=== K3s Server installed ==="

echo "=== start Deployments + Services ==="
kubectl apply -f /vagrant/confs/apps

echo "===start ingress ==="
kubectl apply -f /vagrant/confs/ingress.yaml

echo "=== Checking cluster ==="
kubectl get nodes

echo "=== Checking applications ==="
kubectl get pods

echo "=== Checking services ==="
kubectl get services

echo "=== Checking ingress ==="
kubectl get ingress