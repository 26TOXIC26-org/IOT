#!/bin/bash
set -e
SERVER_IP="192.168.56.110"
IFACE=$(ip -o -4 addr show to "$SERVER_IP" | awk '{print $2}')
rm -f /vagrant/token

curl -sfL https://get.k3s.io | \
    INSTALL_K3S_EXEC="server \
        --node-ip=${SERVER_IP} \
        --advertise-address=${SERVER_IP} \
        --flannel-iface=${IFACE} \
        --disable=traefik \
        --disable=metrics-server \
        --disable=servicelb \
        --disable=local-storage \
        --write-kubeconfig-mode=644" \
    sh -

while [ ! -f /var/lib/rancher/k3s/server/node-token ]; do
    sleep 1
done

cp /var/lib/rancher/k3s/server/node-token /vagrant/token
chmod 644 /vagrant/token
mkdir -p /home/vagrant/.kube
cp /etc/rancher/k3s/k3s.yaml /home/vagrant/.kube/config
chown -R vagrant:vagrant /home/vagrant/.kube

cat << 'EOF' > /usr/local/bin/k
#!/bin/bash
exec /usr/local/bin/k3s kubectl "$@"
EOF

chmod +x /usr/local/bin/k
echo "alias k='kubectl'" >> /home/vagrant/.bashrc
echo "alias k='kubectl'" >> /root/.bashrc