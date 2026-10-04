#!/bin/bash
set -e
SERVER_IP="192.168.56.110"
WORKER_IP="192.168.56.111"
IFACE=$(ip -o -4 addr show to "$WORKER_IP" | awk '{print $2}')

while [ ! -f /vagrant/token ]; do
    sleep 1
done

TOKEN=$(cat /vagrant/token)

curl -sfL https://get.k3s.io | \
    K3S_URL="https://${SERVER_IP}:6443" \
    K3S_TOKEN="${TOKEN}" \
    INSTALL_K3S_EXEC="agent --node-ip=${WORKER_IP} --flannel-iface=${IFACE}" \
    sh -

echo "alias k='kubectl'" >> /home/vagrant/.bashrc
