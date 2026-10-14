# Bonus — GitLab + K3d + Argo CD (GitOps)

Part 3 again, with one change: the Git server is a **GitLab CE that runs inside the same k3d cluster**, in the namespace `gitlab`. Argo CD pulls the app manifests from that local GitLab instead of GitHub. Change the image tag in GitLab (`v1` → `v2`) and Argo CD updates the `dev` namespace by itself.

Who this is for: teammates who must run, explain and defend the bonus.

## Contents

- [Quick start](#quick-start)
- [How it works](#how-it-works)
- [What is where](#what-is-where)
- [Prerequisites](#prerequisites)
- [What the scripts do](#what-the-scripts-do)
- [`confs/gitlab.yaml`, value by value](#confsgitlabyaml-value-by-value)
- [Demo: change the version through GitLab](#demo-change-the-version-through-gitlab)
- [Defense checklist](#defense-checklist)
- [Troubleshooting](#troubleshooting)
- [Reset and cleanup](#reset-and-cleanup)
- [Known limitations](#known-limitations)
- [References](#references)

## Quick start

Run from this folder, on a Debian/Ubuntu VM (amd64) with internet access and about 8 GB of RAM:

```bash
sudo bash scripts/setup.sh             # Docker, kubectl, k3d, cluster, Argo CD, GitLab, then scripts/bootstrap.sh
bash scripts/verify.sh                 # health report, must end with "failed: 0"
```

- Use `bash scripts/…`: the files are not marked executable.
- The first run takes 5 to 30 minutes depending on the VM and the network. Most of it is GitLab: a 1.5 GB image, then its first boot (database migrations). Follow it with `kubectl logs -f gitlab-0 -n gitlab`.
- Every step skips what already exists, so after a failure or a VM reboot just run `setup.sh` again.

When it ends:

| What | How to reach it | Login |
|------|-----------------|-------|
| GitLab | <http://gitlab.local:8080> | `root` / `kubectl get secret gitlab-root-password -n gitlab -o jsonpath='{.data.password}' \| base64 -d; echo` |
| Argo CD | `kubectl port-forward svc/argocd-server -n argocd 8081:443` → <https://localhost:8081> | `admin` / `kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' \| base64 -d; echo` |
| The app | `kubectl port-forward svc/playground-svc -n dev 8888:8888` → `curl http://localhost:8888/` | — |

`gitlab.local` works because `setup.sh` adds `127.0.0.1 gitlab.local` to the VM's `/etc/hosts`. Open GitLab with a browser **inside the VM**. `http://localhost:8080` answers `404`: Traefik routes by host name.

## How it works

```
 you: web UI or git push
   │  http://gitlab.local:8080           (/etc/hosts: 127.0.0.1 gitlab.local)
   ▼
 host port 8080 ─► k3d load balancer ─► Traefik (Ingress rule: Host gitlab.local)
                                          │
 ┌─ k3d cluster "iotcluster" ─────────────┼───────────────────────────────────┐
 │                                        ▼                                   │
 │  ┌─ namespace: gitlab ────────────────────────────────────────────┐        │
 │  │ Service gitlab :80 ─► StatefulSet gitlab ─► Pod gitlab-0       │        │
 │  │   gitlab/gitlab-ce:latest, PVC data-gitlab-0 (10Gi)            │        │
 │  │ project root/iot-gitops-amousaid                               │        │
 │  │   └ manifests/deployment.yaml   (image tag v1 or v2)           │        │
 │  └──────────────────────▲─────────────────────────────────────────┘        │
 │                         │ (1) Argo CD polls Git (~3 min), read-only token  │
 │                         │     http://gitlab.gitlab.svc.cluster.local       │
 │  ┌─ namespace: argocd ──┴────────┐             ┌─ namespace: dev ────────┐ │
 │  │ Argo CD                       │─(2) apply──►│ Deployment              │ │
 │  │ Application: playground       │             │ wil-playground          │ │
 │  │ confs/argocd-app.yaml         │             │ Service playground-svc  │ │
 │  └───────────────────────────────┘             └─────────────────────────┘ │
 └────────────────────────────────────────────────────────────────────────────┘
```

Compared with Part 3, only the Git server changes:

| | Part 3 | Bonus |
|---|---|---|
| Git server | GitHub (public) | **GitLab CE, local**, namespace `gitlab` |
| `repoURL` | `https://github.com/26TOXIC26/iot-gitops-amousaid` | `http://gitlab.gitlab.svc.cluster.local/root/iot-gitops-amousaid.git` |
| `path` | `p3/manifests` | `manifests` |
| Credentials | none (public repo) | private repo, **deploy token** (`read_repository`) in Secret `gitlab-repo` (ns `argocd`) |
| Namespaces | `argocd`, `dev` | `argocd`, `dev`, **`gitlab`** |
| App, cluster, sync policy | `wil42/playground` v1/v2, `iotcluster`, `prune` + `selfHeal` | the same |

**Two URLs for the same GitLab.** The browser uses `http://gitlab.local:8080`: that name only exists in the VM's `/etc/hosts`, and port 8080 only exists on the host (k3d load balancer). Inside the cluster neither works (`localhost` in a Pod is the Pod itself), so Argo CD uses the Service's DNS name `gitlab.gitlab.svc.cluster.local` on port 80. GitLab answers both: its NGINX is the default server, so the host name does not matter.

## What is where

```
bonus/
├── README.md                ← you are here
├── scripts/
│   ├── setup.sh             ← installs the tools and builds the whole lab (run as root, safe to re-run)
│   ├── bootstrap.sh         ← GitLab project + manifests + Argo CD credentials + Application (called by setup.sh)
│   └── verify.sh            ← read-only health report
└── confs/
    ├── gitlab.yaml          ← GitLab: Namespace, Service, StatefulSet (+ PVC), Ingress
    ├── argocd-app.yaml      ← the Argo CD Application: source = local GitLab, destination = dev
    └── manifests/
        └── deployment.yaml  ← the app (Deployment + Service, image v1): pushed to GitLab by bootstrap.sh
```

> **Argo CD does not read `confs/manifests/` in this folder.** `bootstrap.sh` copies `deployment.yaml` into the GitLab project, and Argo CD reads it from there. The version that runs is the one in **GitLab**.

## Prerequisites

- **OS:** Debian or Ubuntu on **amd64** (`apt-get`; `wil42/playground` only exists for amd64).
- **RAM:** 8 GB recommended. The GitLab Pod requests 2.5 GiB and uses about 3 GiB once started; the whole lab (GitLab + Argo CD + K3s) about 4.5 GiB. Add swap on a smaller VM.
- **CPU / disk:** 2 vCPUs minimum (4 is faster), 25 GB free disk (the GitLab image is 1.5 GB compressed).
- **Root:** run through `sudo` (packages, `/usr/local/bin`, `/etc/hosts`).
- **Free host ports:** `8080` (GitLab, through the k3d load balancer), `8081` (Argo CD UI port-forward), `8888` (app port-forward).
- **Internet:** apt repositories, `dl.k8s.io`, `raw.githubusercontent.com`, Docker Hub (`gitlab/gitlab-ce`, `wil42/playground`, `rancher/k3s`), `quay.io` and `ghcr.io` (Argo CD, k3d).
- **Part 3 cluster:** not needed, but no problem if it exists. `setup.sh` reuses `iotcluster` and points the existing `playground` Application to GitLab.

## What the scripts do

### `setup.sh`

`set -euo pipefail`: it stops at the first error. Each step prints `[SKIP]` when there is nothing to do.

| # | Step | Why |
|---|------|-----|
| 1 | `apt-get install` Docker (`docker.io`, only if `docker` is missing), `curl`, `git`, `jq`, `openssl` | k3d needs Docker; `jq`/`openssl` are used by `bootstrap.sh`, `git` by the demo. |
| 2 | Install `kubectl` (latest stable) in a temp dir | Nothing is left in the current directory. |
| 3 | Install k3d (official installer) | |
| 4 | `k3d cluster create iotcluster --servers 1 --agents 0 --port "8080:80@loadbalancer"` (or `k3d cluster start` if it exists); kubeconfig for root and for `$SUDO_USER` | **Same cluster as Part 3.** Host port 8080 now carries GitLab's web UI. |
| 5 | Namespaces `argocd`, `dev`, `gitlab` | `gitlab` is the dedicated namespace the subject asks for. |
| 6 | Secret `gitlab-root-password` (random) + `kubectl apply -f confs/gitlab.yaml` | Before Argo CD, so GitLab's image pull overlaps with the Argo CD install. The password never goes to Git. |
| 7 | Install Argo CD (`stable` manifest, server-side apply) and wait for it | Same as Part 3. |
| 8 | `kubectl rollout status statefulset/gitlab` (up to `GITLAB_WAIT`, default `3600s`) + `/etc/hosts` entry | Waits for GitLab's readiness probe. |
| 9 | `bash scripts/bootstrap.sh` | See below. |

Optional environment variables: `GITLAB_WAIT` (for example `sudo GITLAB_WAIT=5400s bash scripts/setup.sh` on a slow VM) and `GITLAB_ROOT_PASSWORD` (only used the first time the Secret is created).

### `bootstrap.sh`

Can be re-run alone (`bash scripts/bootstrap.sh`). It talks to the GitLab REST API through `http://gitlab.local:8080` (forced to `127.0.0.1` with `curl --resolve`, so it works even without the `/etc/hosts` entry).

| # | Step | Detail |
|---|------|--------|
| 1 | Wait for `/users/sign_in` to answer 200 | through Traefik, like a browser |
| 2 | API token for `root` | reuses Secret `gitlab-bootstrap-token`; otherwise creates a personal access token (scope `api`, 30 days) with `gitlab-rails runner` inside `gitlab-0`. A token of your own also works: `GITLAB_TOKEN=<token> bash scripts/bootstrap.sh` |
| 3 | Project `root/iot-gitops-amousaid` (private, branch `main`) + `manifests/deployment.yaml` | the file is replaced only when it differs from `confs/manifests/deployment.yaml`, which **resets the app to v1** |
| 4 | Deploy token `argocd-read` (scope `read_repository`) → Secret `gitlab-repo` in `argocd`, label `argocd.argoproj.io/secret-type=repository` | least privilege: Argo CD can read this one repo, nothing else. Recreated on every run (GitLab shows a token only once) |
| 5 | `kubectl apply -f confs/argocd-app.yaml`, hard refresh, wait for `Synced/Healthy` **on GitLab's last commit** | prints both commit SHAs: what Argo CD runs = what GitLab holds |

### `verify.sh`

Changes nothing. Checks the namespaces, `gitlab-0` Ready, GitLab's login page through Traefik, the Application (`Synced/Healthy`, `repoURL` = local GitLab), the app Pod, and that the app answers. Prints the GitLab version and the deployed image.

## `confs/gitlab.yaml`, value by value

GitLab runs from the official **Omnibus image** (`gitlab/gitlab-ce`): one container with NGINX, Workhorse, Puma (Rails), Sidekiq, Gitaly, PostgreSQL and Redis. Why not the Helm chart: since chart 10.0 (GitLab 19.0) the chart no longer bundles PostgreSQL, Redis and MinIO (you must install them yourself) and its default ingress moved from NGINX to Gateway API + Envoy Gateway. That is many more Pods and much more RAM than one container, too heavy for a one-VM lab. The subject allows any tool ("helm could be useful").

| Object / field | Value | Why |
|----------------|-------|-----|
| `Namespace` | `gitlab` | Required by the subject. |
| `Service gitlab` | `ClusterIP`, port 80 → container port `http` (80) | Stable in-cluster address: `gitlab.gitlab.svc.cluster.local`. Used by Traefik and Argo CD. |
| `StatefulSet gitlab`, `replicas` | `1` | Stable Pod name (`gitlab-0`) bound to its own PVC. Omnibus is single-node: never more than one replica. |
| `image` | `gitlab/gitlab-ce:latest`, `IfNotPresent` | The latest release from GitLab's official Docker Hub repository (the subject expects the latest version). Not pulled again on restarts. |
| `GITLAB_OMNIBUS_CONFIG` | Ruby, read like `/etc/gitlab/gitlab.rb` at every start | The whole GitLab configuration lives in Git, in this file. |
| `external_url` | `http://gitlab.local:8080` | The address users type: GitLab builds clone URLs and redirects from it. |
| `gitlab_rails['nginx']['listen_port']` | `80` | Without it NGINX would listen on 8080 (the port of `external_url`), but Traefik and the probes reach the Pod on 80. (Key name since GitLab 19.2; it was `nginx['listen_port']` before.) |
| `gitlab_rails['initial_root_password']` | `ENV['GITLAB_ROOT_PASSWORD']` (from Secret `gitlab-root-password`) | Password of `root`, set on the first boot only. |
| `puma`, `sidekiq`, `postgresql`, `gitaly`, `*_exporter`, `prometheus*`, `alertmanager`, `gitlab_kas`… | GitLab's "memory-constrained environment" settings | Single Puma process, Sidekiq concurrency 10, monitoring and KAS off: several hundred MB less RAM. |
| `resources` | request `500m` CPU / `2560Mi`, limit `6Gi` | The request reserves what a tuned GitLab needs; the limit is a safety net for the first boot. |
| `startupProbe` | `/-/readiness?all=1`, 180 × 10 s | Up to 30 minutes for the first boot before Kubernetes gives up. Liveness and readiness start after it succeeds. |
| `readinessProbe` | `/-/readiness?all=1` | Ready only when Rails, PostgreSQL, Redis and Gitaly answer. GitLab's own health endpoints, called from `localhost` (allowed by default). |
| `livenessProbe` | `/-/liveness` | Restart the container if Rails is dead for 5 minutes. |
| `volumeMounts` | one PVC (`data-gitlab-0`, 10Gi, K3s `local-path`), sub-paths `config`, `data`, `logs` | `/etc/gitlab`, `/var/opt/gitlab` (repos, database), `/var/log/gitlab` survive Pod restarts. |
| `/dev/shm` | in-memory `emptyDir`, 256Mi | The container default (64Mi) is too small for PostgreSQL. |
| `Ingress gitlab` | class `traefik`, host `gitlab.local`, `/` → `gitlab:80` | Traefik ships with K3s; the k3d load balancer forwards host port 8080 to it. |

`confs/argocd-app.yaml` is the Part 3 Application with two changes: `repoURL` (the local GitLab) and `path` (`manifests`). Its `repoURL` must be exactly the `url` of Secret `gitlab-repo`: that is how Argo CD finds the credentials.

## Demo: change the version through GitLab

What the evaluator asks for: Part 3's demo, with GitLab as the Git server.

**0. Start from v1.** `bash scripts/bootstrap.sh` puts `confs/manifests/deployment.yaml` (v1) back into GitLab if the repo says something else.

**1. The app answers v1**

```bash
kubectl port-forward svc/playground-svc 8888:8888 -n dev      # terminal 1, leave it running
curl http://localhost:8888/                                    # terminal 2: {"status":"ok", "message": "v1"}
```

**2. Change the tag in GitLab** — either way works:

- **Web UI** (the evaluator sees GitLab): <http://gitlab.local:8080> → log in as `root` → open <http://gitlab.local:8080/root/iot-gitops-amousaid> (right after login GitLab shows a *Create your first project* welcome page: skip it) → `manifests/deployment.yaml` → **Edit** → `wil42/playground:v1` becomes `wil42/playground:v2` → **Commit changes** on `main`.
- **git** from the VM:

  ```bash
  TOKEN=$(kubectl get secret gitlab-bootstrap-token -n gitlab -o jsonpath='{.data.token}' | base64 -d)
  git clone "http://root:${TOKEN}@gitlab.local:8080/root/iot-gitops-amousaid.git" /tmp/iot-gitops && cd /tmp/iot-gitops
  sed -i 's#wil42/playground:v1#wil42/playground:v2#' manifests/deployment.yaml
  git -c user.name=root -c user.email=root@gitlab.local commit -am "v2" && git push
  ```

**3. Argo CD syncs** (within about 3 minutes; to not wait, ask for a refresh):

```bash
kubectl annotate application playground -n argocd argocd.argoproj.io/refresh=hard --overwrite
kubectl get pods -n dev -w                                     # the v2 Pod starts, the v1 Pod terminates
kubectl get application -n argocd                              # playground   Synced   Healthy
```

**4. The app answers v2.** Restart the `port-forward` (the old one was bound to the deleted v1 Pod: `lost connection to pod`), then `curl http://localhost:8888/` → `{"status":"ok", "message": "v2"}`.

**5. Back to v1** for the next demo: same edit with the tags swapped, or `bash scripts/bootstrap.sh`.

Extra, if asked:

- **Self-heal:** `kubectl scale deployment wil-playground -n dev --replicas=3` → Argo CD puts it back to 1.
- **GitLab down:** `kubectl scale statefulset gitlab -n gitlab --replicas=0` → the Application shows `Unknown` (Argo CD cannot read Git) but the app keeps running. Scale back to `1` and it returns to `Synced` after GitLab's boot.
- **Persistence:** `kubectl delete pod gitlab-0 -n gitlab` → a new `gitlab-0` starts on the same PVC; the project, its commits and the root password are still there.

## Defense checklist

The bonus is only graded if Part 1, 2 and 3 are flawless.

- [ ] `bonus/` is at the repo root with `scripts/` and `confs/`.
- [ ] `sudo bash scripts/setup.sh` runs on a clean VM without errors, and `bash scripts/verify.sh` ends with `failed: 0`.
- [ ] `kubectl get ns` shows `argocd`, `dev` **and `gitlab`**.
- [ ] `kubectl get pods -n gitlab` shows `gitlab-0   1/1   Running`; the UI opens at <http://gitlab.local:8080>.
- [ ] The GitLab version is the latest release: `kubectl exec -n gitlab gitlab-0 -- head -1 /opt/gitlab/version-manifest.txt`, compare with <https://hub.docker.com/r/gitlab/gitlab-ce/tags> (or `/help` in the UI).
- [ ] `kubectl get application -n argocd` shows `playground   Synced   Healthy`, and its `repoURL` is the local GitLab (`verify.sh` checks both).
- [ ] **Before starting:** the GitLab repo is at `v1`; `curl` shows `"message": "v1"`.
- [ ] **Live:** change the tag in GitLab, Argo CD syncs, `curl` shows `"message": "v2"`.
- [ ] Be ready to explain: why the Omnibus image and not Helm, how Argo CD reaches GitLab (Service DNS + deploy token), why two URLs, what happens when GitLab is down.

## Troubleshooting

| Symptom | Likely cause | What to do |
|---------|--------------|------------|
| `gitlab-0` stays `0/1 Running` for a long time | First boot (migrations). Normal up to 10–20 minutes on a slow VM. | `kubectl logs -f gitlab-0 -n gitlab`; wait for `gitlab Reconfigured!`. |
| `gitlab-0` `Pending`, event `Insufficient memory` | The VM has less free RAM than the 2560Mi request. | Give the VM more RAM, or lower `requests.memory` in `confs/gitlab.yaml` and add swap. |
| `OOMKilled`, `CrashLoopBackOff` | Not enough RAM. | `kubectl describe pod gitlab-0 -n gitlab`; more RAM or swap. |
| `ImagePullBackOff` | No internet or Docker Hub rate limit (`toomanyrequests`). | `kubectl describe pod gitlab-0 -n gitlab`, read the Events. |
| `setup.sh` stops at step 8 (timeout) | Slow VM or slow download. | Run it again (it resumes), or `sudo GITLAB_WAIT=5400s bash scripts/setup.sh`. |
| Browser: `404 page not found` | Opened `localhost:8080` or the IP: Traefik routes on the host name. | Use <http://gitlab.local:8080>. |
| `Could not resolve host: gitlab.local` | No `/etc/hosts` entry (another machine, or it was removed). | `echo '127.0.0.1 gitlab.local' \| sudo tee -a /etc/hosts` |
| Browser: `502` / "GitLab is not responding" | GitLab is still starting or restarting. | `kubectl exec -n gitlab gitlab-0 -- gitlab-ctl status` |
| `bootstrap.sh`: `[HTTP 401]` | The saved token is no longer valid. | `kubectl delete secret gitlab-bootstrap-token -n gitlab`, run `bootstrap.sh` again. |
| `bootstrap.sh`: "Could not create the token" | `gitlab-rails runner` failed. | Create a token in the UI (avatar → Edit profile → Access tokens, scope `api`), then `GITLAB_TOKEN=<token> bash scripts/bootstrap.sh`. |
| Application `Unknown`, `authentication required` / `repository not found` | Secret `gitlab-repo` missing or stale, or its `url` differs from `repoURL`. | Run `bootstrap.sh` again; `kubectl describe application playground -n argocd`. |
| Application `Unknown`, `connection refused` / `i/o timeout` | GitLab not Ready yet. | `kubectl get endpoints gitlab -n gitlab` must show an IP. |
| `git push`: `HTTP Basic: Access denied` | Wrong token or password. | Use the token from Secret `gitlab-bootstrap-token`, or `root` and its password. |
| Push done but the app did not change | Argo CD has not polled yet. | Hard refresh (demo step 3). |
| `kubectl` fails after a VM reboot | The k3d node containers are stopped. | `sudo bash scripts/setup.sh` (or `sudo k3d cluster start iotcluster`). |

Everything Argo CD complains about is in `kubectl describe application playground -n argocd` (Conditions) and in `kubectl logs -n argocd deploy/argocd-repo-server --tail=50`.

## Reset and cleanup

```bash
k3d cluster delete iotcluster                                          # removes everything, GitLab data included (sudo if needed)
sudo sed -i '/[[:space:]]gitlab\.local\([[:space:]]\|$\)/d' /etc/hosts   # optional: remove the hosts entry
sudo bash scripts/setup.sh                                             # rebuild from scratch
```

## Known limitations

- **HTTP only.** No TLS between you and GitLab, nor between Argo CD and GitLab (that traffic never leaves the cluster). Fine for a local lab.
- **`latest` moves.** GitLab ships a release every month; a new cluster gets the newest image. To freeze a version, replace `latest` with a tag such as `19.4.2-ce.0` in `confs/gitlab.yaml`. Upgrading an existing instance across several minor versions can require GitLab's upgrade stops.
- **Secrets are only base64.** The root password and the tokens live in Kubernetes Secrets (`gitlab-root-password`, `gitlab-bootstrap-token` in `gitlab`, `gitlab-repo` in `argocd`). Delete the cluster (or revoke the tokens in GitLab) after the defense.
- **Overwrites `~/.kube/config`** of the user who ran `sudo`, like Part 3.
- **Debian/Ubuntu on amd64 only.** Nothing is version-pinned: `kubectl` latest stable, k3d latest, Argo CD `stable`, GitLab `latest`.
- **Polling, not webhooks.** Argo CD notices a commit within about 3 minutes unless you trigger a refresh.
- **GitLab is only a Git server here.** No GitLab CI/runners: Argo CD is the CD part.

## References

- Subject: `../subject.pdf`, chapter *V Bonus part* (and *IV.3 Part 3* for what must keep working).
- Part 3: [`../p3/README.md`](../p3/README.md).
- GitLab Docker image: <https://docs.gitlab.com/install/docker/> · tags: <https://hub.docker.com/r/gitlab/gitlab-ce/tags>
- Memory-constrained settings: <https://docs.gitlab.com/omnibus/settings/memory_constrained_envs/>
- Health checks: <https://docs.gitlab.com/administration/monitoring/health_check/>
- Deploy tokens: <https://docs.gitlab.com/user/project/deploy_tokens/> · REST API: <https://docs.gitlab.com/api/rest/>
- Helm chart 10.0 changes: <https://docs.gitlab.com/charts/releases/10_0/>
- Argo CD repository Secrets: <https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#repositories>
