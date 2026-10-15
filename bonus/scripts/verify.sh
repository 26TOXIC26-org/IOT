#!/bin/bash
# Quick health report of the bonus lab. Safe to run any time, changes nothing.
# Usage: bash scripts/verify.sh

GITLAB_HOST="gitlab.local"
GITLAB_PORT="8080"
REPO_URL="http://gitlab.gitlab.svc.cluster.local/root/iot-gitops-amousaid.git" # repoURL of confs/argocd-app.yaml

pass=0
fail=0

check() { # usage: check "description" command [args...]
    local desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "[ OK ] $desc"
        pass=$((pass + 1))
    else
        echo "[FAIL] $desc"
        fail=$((fail + 1))
    fi
}

app_status() {
    kubectl get application playground -n argocd -o jsonpath='{.status.sync.status}/{.status.health.status}'
}

app_repo_url() {
    kubectl get application playground -n argocd -o jsonpath='{.spec.source.repoURL}'
}

dev_pod_phase() {
    kubectl get pods -n dev -l app=playground -o jsonpath='{.items[0].status.phase}'
}

gitlab_http_code() {
    curl -s -o /dev/null -w '%{http_code}' --resolve "${GITLAB_HOST}:${GITLAB_PORT}:127.0.0.1" \
        "http://${GITLAB_HOST}:${GITLAB_PORT}/users/sign_in"
}

echo "== cluster"
check "namespace argocd exists" kubectl get namespace argocd
check "namespace dev exists" kubectl get namespace dev
check "namespace gitlab exists" kubectl get namespace gitlab

echo "== GitLab"
check "pod gitlab-0 is Ready" kubectl wait --for=condition=Ready pod/gitlab-0 -n gitlab --timeout=5s
check "GitLab login page answers 200 through Traefik" test "$(gitlab_http_code)" = "200"
echo "     version : $(kubectl exec -n gitlab gitlab-0 -- head -1 /opt/gitlab/version-manifest.txt 2>/dev/null || echo unknown)"

echo "== Argo CD"
check "Application playground is Synced/Healthy" test "$(app_status)" = "Synced/Healthy"
check "Application pulls from the local GitLab" test "$(app_repo_url)" = "$REPO_URL"

echo "== application"
check "pod in dev is Running" test "$(dev_pod_phase)" = "Running"
echo "     image   : $(kubectl get deployment wil-playground -n dev -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo unknown)"

reply="$(curl -s -m 5 http://localhost:8888/ || true)" # host port 8888 is published by the k3d load balancer (Service type LoadBalancer)
check "the app answers on http://localhost:8888/ (got: ${reply:-nothing})" test -n "$reply"
[ -n "$reply" ] || echo "     hint    : run 'sudo bash scripts/setup.sh' again: it publishes host port 8888 on a cluster created without it"

echo
echo "passed: $pass   failed: $fail"
[ "$fail" -eq 0 ]
