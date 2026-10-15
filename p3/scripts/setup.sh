#!/bin/bash
set -euo pipefail # -e exit on error, -u exit on unset variable, -o pipefail return exit code of last command in pipe that failed

# Usage: sudo bash scripts/setup.sh   (safe to re-run: an existing cluster is started, not recreated)

CLUSTER_NAME="iotcluster"

if [ "$(id -u)" -ne 0 ]; then
    echo "Run this script as root: sudo bash $0" >&2
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a # apt must never stop on an interactive prompt
packages=(ca-certificates curl)
if command -v docker >/dev/null 2>&1; then
    echo "[SKIP] docker already installed" # never swap an existing Docker (docker-ce, ...) for docker.io
else
    packages+=(docker.io)
fi
apt-get update
apt-get install -y "${packages[@]}"

systemctl enable --now docker || echo "[WARN] could not enable the docker service with systemctl"
docker version

if command -v kubectl >/dev/null 2>&1; then
    echo "[SKIP] kubectl already installed"
else
    echo "[INSTALL] kubectl"

    TMP_DIR="$(mktemp -d)" # downloaded in a temp dir, nothing is left in the current directory
    KUBECTL_VERSION="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
    curl -fsSL -o "$TMP_DIR/kubectl" "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/$(dpkg --print-architecture)/kubectl"
    install -m 0755 "$TMP_DIR/kubectl" /usr/local/bin/kubectl
    rm -rf "$TMP_DIR"
fi

if command -v k3d >/dev/null 2>&1; then
    echo "[SKIP] k3d already installed"
else
    echo "[INSTALL] k3d"
    curl -fsSL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
fi

if k3d cluster list "$CLUSTER_NAME" >/dev/null 2>&1; then
    echo "[SKIP] cluster $CLUSTER_NAME already exists"
    k3d cluster start "$CLUSTER_NAME" # wakes it up after a reboot of the VM, nothing to do when it already runs
    if ! docker port "k3d-${CLUSTER_NAME}-serverlb" 8888/tcp >/dev/null 2>&1; then
        echo "[CONFIG] cluster was created without host port 8888: publishing it now"
        k3d cluster edit "$CLUSTER_NAME" --port-add "8888:8888@loadbalancer" # only the load balancer container is recreated
    fi
    k3d kubeconfig merge "$CLUSTER_NAME" --kubeconfig-merge-default --kubeconfig-switch-context >/dev/null # kubectl of root talks to this cluster
else
    k3d cluster create "$CLUSTER_NAME" \
      --servers 1 \
      --agents 0 \
      --port "8080:80@loadbalancer" \
      --port "8888:8888@loadbalancer"
fi

# --------------------------------------------------
# Configure kubeconfig for the real user
# --------------------------------------------------
REAL_USER="${SUDO_USER:-${USER:-root}}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

if [ "$REAL_USER" != "root" ]; then
    echo "[CONFIG] kubeconfig for $REAL_USER"

    mkdir -p "$REAL_HOME/.kube"

    # merge, never overwrite: the other clusters of that user stay in the file
    k3d kubeconfig merge "$CLUSTER_NAME" --output "$REAL_HOME/.kube/config" --kubeconfig-switch-context >/dev/null

    chown -R "$REAL_USER:" "$REAL_HOME/.kube" # mkdir and k3d ran as root: the user must own the folder, not only the file
    chmod 600 "$REAL_HOME/.kube/config"

    echo "[OK] kubeconfig configured at $REAL_HOME/.kube/config"
fi

kubectl get nodes

for ns in argocd dev; do
    kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done

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
