#!/bin/bash
set -euo pipefail # -e exit on error, -u exit on unset variable, -o pipefail return exit code of last command in pipe that failed

# Bonus = Part 3 (k3d + Argo CD) + a local GitLab CE that lives in the "gitlab" namespace.
# Usage: sudo bash scripts/setup.sh   (safe to re-run: every step skips what already exists)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFS_DIR="$SCRIPT_DIR/../confs"

CLUSTER_NAME="iotcluster"
GITLAB_HOST="gitlab.local"
GITLAB_WAIT="${GITLAB_WAIT:-3600s}" # image pull (about 1.5 GB) + first boot of GitLab (reconfigure + migrations) is slow

log() { echo; echo "==> $*"; }

if [ "$(id -u)" -ne 0 ]; then
    echo "Run this script as root: sudo bash $0" >&2
    exit 1
fi

# --------------------------------------------------
# 1. Docker + small helpers (git for the demo, jq and openssl are used by bootstrap.sh)
# --------------------------------------------------
log "[1/9] Docker and helper packages"
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a # apt must never stop on an interactive prompt
packages=(ca-certificates curl git jq openssl)
if command -v docker >/dev/null 2>&1; then
    echo "[SKIP] docker already installed" # never swap an existing Docker (docker-ce, ...) for docker.io
else
    packages+=(docker.io)
fi
apt-get update
apt-get install -y "${packages[@]}"

systemctl enable --now docker || echo "[WARN] could not enable the docker service with systemctl"
docker version

# --------------------------------------------------
# 2. kubectl (downloaded in a temp dir, nothing is left in the current directory)
# --------------------------------------------------
log "[2/9] kubectl"
if command -v kubectl >/dev/null 2>&1; then
    echo "[SKIP] kubectl already installed"
else
    TMP_DIR="$(mktemp -d)"
    KUBECTL_VERSION="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
    curl -fsSL -o "$TMP_DIR/kubectl" "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/$(dpkg --print-architecture)/kubectl"
    install -m 0755 "$TMP_DIR/kubectl" /usr/local/bin/kubectl
    rm -rf "$TMP_DIR"
fi

# --------------------------------------------------
# 3. k3d
# --------------------------------------------------
log "[3/9] k3d"
if command -v k3d >/dev/null 2>&1; then
    echo "[SKIP] k3d already installed"
else
    curl -fsSL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
fi

# --------------------------------------------------
# 4. Cluster (same flags as Part 3: host port 8080 -> k3d load balancer port 80 -> Traefik)
# --------------------------------------------------
log "[4/9] k3d cluster $CLUSTER_NAME"
if k3d cluster list -o json | jq -e --arg n "$CLUSTER_NAME" '.[] | select(.name == $n)' >/dev/null; then
    echo "[SKIP] cluster $CLUSTER_NAME already exists"
    k3d cluster start "$CLUSTER_NAME" # wakes it up after a reboot of the VM, nothing to do when it already runs
else
    k3d cluster create "$CLUSTER_NAME" \
      --servers 1 \
      --agents 0 \
      --port "8080:80@loadbalancer"
fi
k3d kubeconfig merge "$CLUSTER_NAME" --kubeconfig-merge-default --kubeconfig-switch-context >/dev/null # kubectl of root talks to this cluster

# --------------------------------------------------
# Configure kubeconfig for the real user
# --------------------------------------------------
REAL_USER="${SUDO_USER:-${USER:-root}}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

if [ "$REAL_USER" != "root" ]; then
    echo "[CONFIG] kubeconfig for $REAL_USER"

    mkdir -p "$REAL_HOME/.kube"

    k3d kubeconfig get "$CLUSTER_NAME" > "$REAL_HOME/.kube/config"

    chown "$REAL_USER:$REAL_USER" "$REAL_HOME/.kube/config"
    chmod 600 "$REAL_HOME/.kube/config"

    echo "[OK] kubeconfig configured at $REAL_HOME/.kube/config"
fi

kubectl get nodes

# --------------------------------------------------
# 5. Namespaces: argocd (Argo CD), dev (the app), gitlab (GitLab)
# --------------------------------------------------
log "[5/9] namespaces"
for ns in argocd dev gitlab; do
    kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done

# --------------------------------------------------
# 6. GitLab: root password (Secret, not in Git) + StatefulSet/Service/Ingress.
#    Applied BEFORE Argo CD so the image pull and first boot overlap with the Argo CD install.
# --------------------------------------------------
log "[6/9] GitLab manifests"
if kubectl get secret gitlab-root-password -n gitlab >/dev/null 2>&1; then
    echo "[SKIP] secret gitlab-root-password already exists"
else
    kubectl create secret generic gitlab-root-password -n gitlab \
      --from-literal=password="${GITLAB_ROOT_PASSWORD:-Iot-$(openssl rand -hex 10)}"
fi

kubectl apply -f "$CONFS_DIR/gitlab.yaml"

# --------------------------------------------------
# 7. Argo CD (same as Part 3)
# --------------------------------------------------
log "[7/9] Argo CD"
kubectl apply -n argocd \
  --server-side \
  --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl wait --for=condition=Available \
  deployment/argocd-server \
  deployment/argocd-repo-server \
  --timeout=600s \
  -n argocd

kubectl rollout status statefulset/argocd-application-controller \
  -n argocd \
  --timeout=600s

# --------------------------------------------------
# 8. Wait for GitLab, and make gitlab.local resolve on this machine
# --------------------------------------------------
log "[8/9] waiting for GitLab (first run: 5 to 20 minutes, follow it with: kubectl logs -f gitlab-0 -n gitlab)"
kubectl rollout status statefulset/gitlab -n gitlab --timeout="$GITLAB_WAIT"

if grep -qE "^[^#]*[[:space:]]${GITLAB_HOST}([[:space:]]|\$)" /etc/hosts; then
    echo "[SKIP] $GITLAB_HOST already in /etc/hosts"
else
    echo "127.0.0.1 $GITLAB_HOST" >> /etc/hosts
    echo "[OK] added '127.0.0.1 $GITLAB_HOST' to /etc/hosts"
fi

# --------------------------------------------------
# 9. GitLab project + manifests + Argo CD credentials + Application
# --------------------------------------------------
log "[9/9] bootstrap (project, manifests, Argo CD repository, Application)"
bash "$SCRIPT_DIR/bootstrap.sh"

echo
echo "GitLab    : http://${GITLAB_HOST}:8080   (user: root)"
echo "Password  : kubectl get secret gitlab-root-password -n gitlab -o jsonpath='{.data.password}' | base64 -d; echo"
echo "Argo CD   : kubectl port-forward svc/argocd-server -n argocd 8081:443   ->  https://localhost:8081   (user: admin)"
echo "Password  : kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d; echo"
echo "The app   : kubectl port-forward svc/playground-svc -n dev 8888:8888    ->  curl http://localhost:8888/"
