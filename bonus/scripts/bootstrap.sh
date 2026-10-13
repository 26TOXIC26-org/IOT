#!/bin/bash
set -euo pipefail # -e exit on error, -u exit on unset variable, -o pipefail return exit code of last command in pipe that failed

# Runs once GitLab is up (called by setup.sh, but can be re-run on its own: it is idempotent).
#   1. wait for the GitLab web UI
#   2. get an API token for root (GITLAB_TOKEN if you already have one, otherwise created with gitlab-rails runner)
#   3. create the project root/iot-gitops-amousaid and push confs/manifests/deployment.yaml (resets it to v1)
#   4. create a read-only deploy token and give it to Argo CD (Secret in the argocd namespace)
#   5. apply the Argo CD Application and wait until it is Synced/Healthy on the last commit of GitLab

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFS_DIR="$SCRIPT_DIR/../confs"
MANIFESTS_DIR="$CONFS_DIR/manifests"

GITLAB_HOST="gitlab.local"
GITLAB_PORT="8080"
GITLAB_URL="http://${GITLAB_HOST}:${GITLAB_PORT}"
PROJECT="root/iot-gitops-amousaid"
PROJECT_ENC="${PROJECT//\//%2F}" # root%2Fiot-gitops-amousaid: the API accepts the URL-encoded path as project id
BRANCH="main"
INTERNAL_REPO_URL="http://gitlab.gitlab.svc.cluster.local/${PROJECT}.git" # must be the repoURL of confs/argocd-app.yaml

log() { echo; echo "==> $*"; }

# curl wrapper: always talks to the k3d load balancer on 127.0.0.1, whatever DNS says.
# Prints the body; returns non-zero when the HTTP status is not 2xx.
gl_api() { # usage: gl_api METHOD /path [extra curl args]
    local method="$1" path="$2" out code
    shift 2
    out="$(mktemp)"
    code="$(curl -sS -o "$out" -w '%{http_code}' -X "$method" \
        --resolve "${GITLAB_HOST}:${GITLAB_PORT}:127.0.0.1" \
        -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
        "$@" "${GITLAB_URL}/api/v4${path}")" || { rm -f "$out"; return 1; }
    cat "$out"
    rm -f "$out"
    case "$code" in
        2??) return 0 ;;
        *) echo "[HTTP $code] $method $path" >&2; return 1 ;;
    esac
}

# --------------------------------------------------
# 1. wait for the web UI (Traefik -> nginx -> workhorse -> puma)
# --------------------------------------------------
log "waiting for $GITLAB_URL"
ready=false
code="000"
for i in $(seq 1 90); do
    code="$(curl -s -o /dev/null -w '%{http_code}' --resolve "${GITLAB_HOST}:${GITLAB_PORT}:127.0.0.1" "${GITLAB_URL}/users/sign_in" || true)"
    if [ "$code" = "200" ]; then
        ready=true
        break
    fi
    if [ $((i % 6)) -eq 0 ]; then
        echo "  still waiting (HTTP $code), ${i}0s elapsed..."
    fi
    sleep 10
done
if [ "$ready" != "true" ]; then
    echo "GitLab did not answer 200 on $GITLAB_URL/users/sign_in (last status: $code)" >&2
    exit 1
fi
echo "[OK] GitLab answers"

# --------------------------------------------------
# 2. API token for root: given by the caller, or kept in a Secret from a previous run, or created now
# --------------------------------------------------
GITLAB_TOKEN="${GITLAB_TOKEN:-}"
if [ -z "$GITLAB_TOKEN" ]; then
    GITLAB_TOKEN="$(kubectl get secret gitlab-bootstrap-token -n gitlab -o jsonpath='{.data.token}' 2>/dev/null | base64 -d 2>/dev/null || true)"
fi

if [ -n "$GITLAB_TOKEN" ] && gl_api GET /user >/dev/null 2>&1; then
    echo "[SKIP] reusing the existing API token"
else
    log "creating a personal access token for root (gitlab-rails runner, about 1 minute)"
    GITLAB_TOKEN="$(openssl rand -hex 10)" # GitLab wants exactly 20 characters
    if ! kubectl exec -n gitlab gitlab-0 -- gitlab-rails runner "
        user = User.find_by_username('root')
        token = user.personal_access_tokens.create(scopes: ['api'], name: 'iot-bootstrap-$(date +%s)', expires_at: 30.days.from_now)
        token.set_token('${GITLAB_TOKEN}')
        token.save!
    "; then
        echo "Could not create the token with gitlab-rails runner." >&2
        echo "Create one by hand (GitLab > avatar > Edit profile > Access tokens, scope: api), then run:" >&2
        echo "  GITLAB_TOKEN=<your token> bash $0" >&2
        exit 1
    fi
    kubectl create secret generic gitlab-bootstrap-token -n gitlab \
        --from-literal=token="$GITLAB_TOKEN" \
        --dry-run=client -o yaml | kubectl apply -f -
fi
gl_api GET /user | jq -r '"[OK] API token works, authenticated as " + .username'

# --------------------------------------------------
# 3. project + manifests
# --------------------------------------------------
log "project $PROJECT"
if gl_api GET "/projects/${PROJECT_ENC}" >/dev/null 2>&1; then
    echo "[SKIP] project already exists"
else
    gl_api POST /projects \
        --data-urlencode "name=${PROJECT#*/}" \
        --data-urlencode "visibility=private" \
        --data-urlencode "initialize_with_readme=true" \
        --data-urlencode "default_branch=${BRANCH}" >/dev/null
    echo "[OK] project created"
fi

push_file() { # usage: push_file LOCAL_FILE PATH_IN_REPO
    local file="$1" repo_path="$2" enc current method
    enc="$(jq -rn --arg p "$repo_path" '$p | @uri')"
    current="$(mktemp)"
    if gl_api GET "/projects/${PROJECT_ENC}/repository/files/${enc}/raw?ref=${BRANCH}" > "$current" 2>/dev/null; then
        if cmp -s "$current" "$file"; then
            rm -f "$current"
            echo "[SKIP] $repo_path is already up to date"
            return 0
        fi
        method="PUT"
    else
        method="POST"
    fi
    rm -f "$current"
    gl_api "$method" "/projects/${PROJECT_ENC}/repository/files/${enc}" \
        --data-urlencode "branch=${BRANCH}" \
        --data-urlencode "commit_message=bootstrap: ${repo_path}" \
        --data-urlencode "content@${file}" >/dev/null
    echo "[OK] $repo_path pushed ($method)"
}

push_file "$MANIFESTS_DIR/deployment.yaml" "manifests/deployment.yaml"

# --------------------------------------------------
# 4. read-only deploy token -> Argo CD repository credentials
# --------------------------------------------------
log "deploy token for Argo CD (scope: read_repository)"
for id in $(gl_api GET "/projects/${PROJECT_ENC}/deploy_tokens" | jq -r '.[] | select(.name == "argocd-read") | .id'); do
    gl_api DELETE "/projects/${PROJECT_ENC}/deploy_tokens/${id}" >/dev/null
done
resp="$(gl_api POST "/projects/${PROJECT_ENC}/deploy_tokens" \
    -H "Content-Type: application/json" \
    --data '{"name":"argocd-read","username":"argocd","scopes":["read_repository"]}')"
DEPLOY_USER="$(jq -r '.username' <<<"$resp")"
DEPLOY_TOKEN="$(jq -r '.token' <<<"$resp")"

kubectl create secret generic gitlab-repo -n argocd \
    --from-literal=type=git \
    --from-literal=url="$INTERNAL_REPO_URL" \
    --from-literal=username="$DEPLOY_USER" \
    --from-literal=password="$DEPLOY_TOKEN" \
    --dry-run=client -o yaml \
  | kubectl label --local -f - argocd.argoproj.io/secret-type=repository -o yaml \
  | kubectl apply -f - # the label is what makes Argo CD read this Secret as a repository

# --------------------------------------------------
# 5. Argo CD Application, then wait until Argo CD runs the last commit of GitLab
# --------------------------------------------------
log "Argo CD Application"
HEAD_SHA="$(gl_api GET "/projects/${PROJECT_ENC}/repository/branches/${BRANCH}" | jq -r '.commit.id')"
kubectl apply -f "$CONFS_DIR/argocd-app.yaml"
kubectl annotate application playground -n argocd argocd.argoproj.io/refresh=hard --overwrite

status=""
for _ in $(seq 1 60); do
    status="$(kubectl get application playground -n argocd -o jsonpath='{.status.sync.status}/{.status.health.status} {.status.sync.revision}' 2>/dev/null || true)"
    if [ "$status" = "Synced/Healthy ${HEAD_SHA}" ]; then
        break
    fi
    sleep 5
done
echo "Application playground: ${status:-unknown}   (GitLab ${BRANCH} is at ${HEAD_SHA})"
if [ "$status" != "Synced/Healthy ${HEAD_SHA}" ]; then
    echo "Not Synced/Healthy on the last commit yet. Look at: kubectl describe application playground -n argocd" >&2
    exit 1
fi
