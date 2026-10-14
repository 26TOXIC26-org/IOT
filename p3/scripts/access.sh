#!/usr/bin/env bash

set -euo pipefail

cleanup() {
  trap - EXIT INT TERM
  kill $(jobs -pr) 2>/dev/null || true
  wait 2>/dev/null || true
}
trap cleanup EXIT INT TERM

kubectl port-forward -n dev service/playground 8888:8888 &
kubectl port-forward -n argocd service/argocd-server 8080:443 &

echo "Application: http://localhost:8888"
echo "Argo CD:     https://localhost:8080"
echo "Argo CD user: admin"
echo -n "Argo CD password: "
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 --decode
echo
echo "Press Ctrl-C to stop port forwarding."

wait
