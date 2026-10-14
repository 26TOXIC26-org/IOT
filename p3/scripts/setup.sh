#!/usr/bin/env bash

set -euo pipefail

CLUSTER_NAME="iot-cluster"
ARGOCD_MANIFEST="https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONF_DIR="$(cd -- "${SCRIPT_DIR}/../confs" && pwd)"

for command_name in docker kubectl k3d; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing $command_name. Run install.sh first." >&2
    exit 1
  fi
done

if ! docker info >/dev/null 2>&1; then
  echo "Docker is not accessible. Start Docker and check your docker group." >&2
  exit 1
fi

if ! k3d cluster list --no-headers | awk '{print $1}' | grep -qx "$CLUSTER_NAME"; then
  k3d cluster create "$CLUSTER_NAME"
fi

kubectl config use-context "k3d-${CLUSTER_NAME}"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace dev --dry-run=client -o yaml | kubectl apply -f -

kubectl apply --server-side --force-conflicts -n argocd -f "$ARGOCD_MANIFEST"
kubectl wait --for=condition=Available deployment --all -n argocd --timeout=300s
kubectl rollout status statefulset/argocd-application-controller -n argocd --timeout=300s

kubectl apply -f "${CONF_DIR}/../application.yaml"
kubectl wait --for=jsonpath='{.status.sync.status}'=Synced \
  application/playground -n argocd --timeout=300s
kubectl wait --for=jsonpath='{.status.health.status}'=Healthy \
  application/playground -n argocd --timeout=300s
kubectl rollout status deployment/playground -n dev --timeout=300s

echo "Part 3 is ready. Run access.sh to access the application and Argo CD."

