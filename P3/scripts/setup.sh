#!/bin/bash
set -euo pipefail # -e exit on error, -u exit on unset variable, -o pipefail return exit code of last command in pipe that failed

apt-get update
apt-get install -y docker.io ca-certificates curl

systemctl enable --now docker
docker version

if command -v kubectl >/dev/null 2>&1; then
    echo "[SKIP] kubectl already installed"
else
    echo "[INSTALL] kubectl"

    apt-get update
    apt-get install -y ca-certificates curl

    KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
    curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
    install -m 0755 kubectl /usr/local/bin/kubectl
    rm -f kubectl
fi

curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

k3d cluster create iotcluster \
  --servers 1 \
  --agents 1 \
  --port "8080:80@loadbalancer"

# --------------------------------------------------
# Configure kubeconfig for the real user
# --------------------------------------------------
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

if [ "$REAL_USER" != "root" ]; then
    echo "[CONFIG] kubeconfig for $REAL_USER"

    mkdir -p "$REAL_HOME/.kube"

    k3d kubeconfig get iotcluster > "$REAL_HOME/.kube/config"

    chown "$REAL_USER:$REAL_USER" "$REAL_HOME/.kube/config"
    chmod 600 "$REAL_HOME/.kube/config"

    echo "[OK] kubeconfig configured at $REAL_HOME/.kube/config"
fi

kubectl get nodes

kubectl create namespace argocd
kubectl create namespace dev

kubectl apply -n argocd \
  --server-side \
  --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl wait --for=condition=Available \
  deployment/argocd-server \
  deployment/argocd-repo-server \
  --timeout=300s \
  -n argocd

kubectl rollout status statefulset/argocd-application-controller \
  -n argocd \
  --timeout=300s

kubectl apply -f "$(dirname "${BASH_SOURCE[0]}")/../confs/argocd-app.yaml"
