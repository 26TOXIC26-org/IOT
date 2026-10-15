# Part 3 — K3d + Argo CD (GitOps)

A one-VM Kubernetes lab. **k3d** runs a [K3s](https://k3s.io/) cluster inside Docker, **Argo CD** is installed in that cluster, and Argo CD keeps the `dev` namespace in sync with a **public GitHub repository**. Change the image tag in Git (`v1` → `v2`) and the cluster updates itself — nobody runs `kubectl apply` by hand. That is *GitOps*: Git is the single source of truth, and the cluster **pulls** from it.

Who this is for: teammates who must run, explain and defend Part 3.

## Contents

- [Part 3 — K3d + Argo CD (GitOps)](#part-3--k3d--argo-cd-gitops)
  - [Contents](#contents)
  - [Quick start](#quick-start)
  - [How it works](#how-it-works)
  - [What is where](#what-is-where)
    - [Which version is deployed?](#which-version-is-deployed)
  - [Prerequisites](#prerequisites)
  - [What `setup.sh` does](#what-setupsh-does)
  - [The config files, value by value](#the-config-files-value-by-value)
    - [`confs/argocd-app.yaml` — the Argo CD Application](#confsargocd-appyaml--the-argo-cd-application)
    - [`manifests/deployment.yaml` — what gets deployed](#manifestsdeploymentyaml--what-gets-deployed)
  - [Using the lab](#using-the-lab)
    - [Check the state](#check-the-state)
    - [Open the Argo CD UI](#open-the-argo-cd-ui)
    - [Reach the app](#reach-the-app)
    - [Demo: change the version through Git](#demo-change-the-version-through-git)
    - [Optional: watch self-heal work](#optional-watch-self-heal-work)
  - [Defense checklist](#defense-checklist)
  - [K3s vs K3d](#k3s-vs-k3d)
  - [Troubleshooting](#troubleshooting)
  - [Reset and cleanup](#reset-and-cleanup)
  - [Known limitations](#known-limitations)
  - [References](#references)

## Quick start

Run from this folder, on a Debian/Ubuntu VM with internet access:

```bash
sudo bash scripts/setup.sh             # installs Docker, kubectl, k3d; builds the cluster; installs Argo CD

kubectl get ns                         # argocd and dev exist
kubectl get app -n argocd              # playground   Synced   Healthy
kubectl get pods -n dev                # wil-playground-<hash>   1/1   Running
curl http://localhost:8888/            # {"status":"ok", "message": "v1"}   (or "v2")
```

The app answers on host port **8888** directly: its Service is `type: LoadBalancer` and the cluster publishes that port (`--port "8888:8888@loadbalancer"`). No `kubectl port-forward` is needed, and the same `curl` keeps working after the v1 → v2 update.

- Use `bash scripts/setup.sh` — the file is not marked executable.
- Safe to re-run: an existing `iotcluster` is started (not recreated) and existing namespaces are left alone, so the script also brings the lab back after a reboot of the VM.
- The first Argo CD sync runs in the background after the script ends. Give it a minute or two (image pulls dominate): `curl` answers once the Pod is `Running`.
- The version you get is the tag in the **GitOps repo**, not the copy in this folder. See [Which version is deployed?](#which-version-is-deployed).

## How it works

```
   Developer
       │ (A) git push: change the image tag, v1 -> v2
       │
       ▼
 ┌─────────────────────────────────┐           ┌────────────────────────────┐
 │ GitHub (public repo)            │           │ Docker Hub                 │
 │ 26TOXIC26/iot-gitops-amousaid   │           │ wil42/playground           │
 │ └ p3/manifests/deployment.yaml  │           │ tags: v1, v2               │
 └─────────────────────────────────┘           └────────────────────────────┘
                           │                                  │
     (1) Argo CD polls Git │                   (4) containerd │
 about every 3 min (HTTPS) │                  pulls the image │
 ┌─────────────────────────┼─── k3d cluster "iotcluster" ─────┼─────────────┐
 │                         │                                  │             │
 │  ┌─ namespace: argocd ──▼──┐          ┌─ namespace: dev ───▼──────────┐  │
 │  │ Argo CD                 │ (2)      │ Deployment wil-playground     │  │
 │  │ Application: playground │─────────►│  └ ReplicaSet                 │  │
 │  │ (confs/argocd-app.yaml) │ apply    │     └ Pod  wil42/playground   │  │
 │  │                         │          │      (3) scheduled to a node  │  │
 │  │ watches Git, syncs      │          │                               │  │
 │  └─────────────────────────┘          │ Service playground-svc        │  │
 │                                       │  8888 -> 8888  (LoadBalancer) │  │
 │                                       │  (5) routes to Pod by label   │  │
 │                                       └───────────────▲───────────────┘  │
 │ (Docker on one VM: 1 server node)                     │                  │
 └───────────────────────────────────────────────────────┼──────────────────┘
                                                         │
                                                         │
                                        you: curl http://localhost:8888/
                                        (host 8888 -> k3d load balancer -> node -> Pod)
```

| Step | What happens | Done by | See it with |
|------|--------------|---------|-------------|
| A | Someone edits `p3/manifests/deployment.yaml` in the GitOps repo (for example tag `v1` → `v2`) and pushes to `main`. | you | `git log` in the GitOps repo |
| 1 | Argo CD fetches the repo (`repoURL`, `targetRevision`, `path`) and renders the YAML in `p3/manifests`. | `argocd-repo-server` clones and renders; `argocd-application-controller` compares Git with the cluster | `kubectl get app -n argocd` (SYNC STATUS) |
| 2 | Any difference is applied to the cluster through the Kubernetes API, into namespace `dev`. | `argocd-application-controller` → API server | `kubectl get all -n dev` |
| 3 | The Deployment creates a ReplicaSet, the ReplicaSet creates the Pod; the scheduler picks a node and that node's kubelet starts the Pod. | Kubernetes controllers, scheduler, kubelet | `kubectl get pods -n dev -o wide` (NODE column) |
| 4 | The node's container runtime (containerd) pulls `wil42/playground:<tag>` from Docker Hub and starts the container. | containerd | `kubectl describe pod -n dev -l app=playground` (Events) |
| 5 | The Service gives the Pods one stable address and load-balances to every Pod labelled `app=playground`. | Service + kube-proxy | `kubectl get svc,endpoints -n dev` |

The numbers match the drawing on the **P3 GitOps Flow (Argo CD)** page of [`../K8S.drawio`](../K8S.drawio). The other pages there (*K8s Objects Glossary*, *ArgoCD Objects Glossary*) explain every object and component used here.

**Why "pull"?** Argo CD only makes outbound HTTPS calls to GitHub. Nothing outside the cluster needs credentials or network access *into* it. Argo CD compares the **desired state** (YAML in Git) with the **live state** (objects in the cluster); whatever differs is `OutOfSync`, and because automated sync is enabled Argo CD fixes it by applying the Git version.

## What is where

Two different repositories are involved. Do not mix them up.

| | This repo (the deliverable) | The GitOps repo (what runs) |
|---|---|---|
| URL | <https://github.com/26TOXIC26/IOT> | <https://github.com/26TOXIC26/iot-gitops-amousaid> |
| Holds | the install script and the Argo CD configuration (what gets graded) | the manifests Argo CD deploys: `p3/manifests/deployment.yaml` |
| Who reads it | people, evaluators | Argo CD, inside the cluster |
| Rules | folder layout from the subject (`p3/scripts`, `p3/confs`) | **must be public**; its name must contain the login of a group member (subject) |

Contents of this folder:

```
.                        ← this folder
├── README.md            ← you are here
├── scripts/
│   └── setup.sh         ← installs the tools and bootstraps the whole lab (run as root)
└── confs/
    └── argocd-app.yaml  ← the Argo CD "Application": what to deploy, from where, to where
```

> **The app manifests are not in this folder.** Argo CD reads `p3/manifests/deployment.yaml` from the GitOps repo (lowercase `p3`, the path is case-sensitive). This repo only holds the script and the `Application` that points to it.

### Which version is deployed?

Ask the GitOps repo, not this folder:

```bash
curl -s https://raw.githubusercontent.com/26TOXIC26/iot-gitops-amousaid/main/p3/manifests/deployment.yaml | grep 'image:'
```

Argo CD deploys whatever tag this prints. A fresh `setup.sh` run deploys the tag that is on `main` **right now**, so before a demo make sure it prints `:v1` (reset it first if it does not).

## Prerequisites

- **OS:** Debian or Ubuntu (the script uses `apt-get`, `dpkg` and `systemctl`) on **amd64** (`wil42/playground` is only published for amd64).
- **Root:** run through `sudo` (installs packages, writes to `/usr/local/bin`, manages the Docker service).
- **Internet:** apt repositories, `dl.k8s.io`, `raw.githubusercontent.com` (k3d installer and Argo CD manifests), Docker Hub, the registries Argo CD's images come from (for example `quay.io`, `ghcr.io`), and `github.com` (Argo CD clones the GitOps repo).
- **Free host ports:** `8080` (Ingress, unused today) and `8888` (the app). Both are published by the k3d load balancer, so the cluster cannot be created if one of them is taken. `8081` is only used by the Argo CD UI `port-forward`.
- **Size (rule of thumb, not a requirement):** about 2 vCPUs and 4 GB of RAM is comfortable for k3d + Argo CD.

## What `setup.sh` does

The script starts with `set -euo pipefail`: it stops at the first error, on any unset variable, and when any command in a pipe fails. It then checks that it runs as root and exits with a message if not.

| # | Step | Command | Why |
|---|------|---------|-----|
| 1 | Install Docker | `apt-get install -y ca-certificates curl`, plus `docker.io` **only if `docker` is missing**; `systemctl enable --now docker` | k3d runs every Kubernetes node as a Docker container, so Docker is the one hard dependency. An existing Docker (for example `docker-ce`) is never replaced, and `apt` runs non-interactive so it cannot stop on a prompt. |
| 2 | Install `kubectl` (skipped if present) | download latest stable from `dl.k8s.io` into a temp folder (architecture from `dpkg`), `install -m 0755` into `/usr/local/bin` | The command-line client for the cluster. Nothing is left in the current directory. |
| 3 | Install k3d (skipped if present) | official `install.sh` piped to `bash` | Installs the latest k3d release. |
| 4 | Create the cluster (or start it) | `k3d cluster create iotcluster --servers 1 --agents 0 --port "8080:80@loadbalancer" --port "8888:8888@loadbalancer"`; if `iotcluster` already exists: `k3d cluster start iotcluster`, plus `k3d cluster edit iotcluster --port-add "8888:8888@loadbalancer"` when it does not publish 8888 yet | See the flag table below. An existing cluster is reused, never recreated; `start` also wakes it up after a reboot, and `edit --port-add` only recreates the load-balancer container, so a cluster made by an older version of the script gets port 8888 without losing anything. |
| 5 | Give your user access | `k3d kubeconfig merge iotcluster --output ~/.kube/config` for `$SUDO_USER`, then `chown -R` of `~/.kube` | So `kubectl` works without `sudo`. **Merges** into the existing file (your other clusters stay) and makes `k3d-iotcluster` the current context. Skipped when run as plain root. |
| 6 | Create namespaces | `kubectl create namespace <ns> --dry-run=client -o yaml \| kubectl apply -f -` for `argocd` and `dev` | One for Argo CD, one for the app (subject requirement). `apply` makes it a no-op when a namespace already exists. |
| 7 | Install Argo CD | `kubectl apply -n argocd --server-side --force-conflicts -f …/argo-cd/stable/manifests/install.yaml` | Official install manifest. Server-side apply is needed because some Argo CD CRDs (notably ApplicationSet) are too large for client-side apply's `last-applied` annotation (262 144-byte limit). |
| 8 | Wait until ready | `kubectl wait --for=condition=Available` on `argocd-server` and `argocd-repo-server`; `kubectl rollout status` on `argocd-application-controller` | Argo CD must be running before it is given work. |
| 9 | Hand over to GitOps | `kubectl apply -f confs/argocd-app.yaml` | Last, because the `Application` kind only exists once Argo CD's CRDs are installed. From here on Argo CD deploys the app. |

The path to `confs/` is resolved relative to the script, so it can be started from any directory.

**The cluster flags**

| Flag | Meaning |
|------|---------|
| `iotcluster` | Cluster name. k3d names its containers `k3d-iotcluster-server-0` (the node) and `k3d-iotcluster-serverlb` (the load balancer). |
| `--servers 1` | One K3s *server* node: the control plane (API server, scheduler, controller manager, datastore). A K3s server also runs the kubelet and is not tainted, so Pods are scheduled on it too. |
| `--agents 0` | No separate *agent* (worker) node: one node is enough for Argo CD and the app. This is also k3d's default; the flag is written out to show the choice. |
| `--port "8080:80@loadbalancer"` | Publish host port 8080 on port 80 of k3d's load-balancer container (where Traefik, the Ingress controller of K3s, listens). It is **not used by the app**: it exists for a future Ingress. |
| `--port "8888:8888@loadbalancer"` | Publish host port 8888 on port 8888 of the node through the load balancer. K3s's built-in ServiceLB opens that port for the Service `playground-svc` (`type: LoadBalancer`), so `curl http://localhost:8888/` reaches the Pod directly. |

**What you have afterwards:** `kubectl get nodes` shows one node (`control-plane`, which also runs Pods); `docker ps` shows the two `k3d-iotcluster-*` containers; and Argo CD runs in `argocd`:

| Pod (namespace `argocd`) | Role |
|--------------------------|------|
| `argocd-server` | API and web UI |
| `argocd-repo-server` | clones Git and renders manifests |
| `argocd-application-controller` (StatefulSet) | compares Git with the cluster and syncs — the core |
| `argocd-redis` | cache |
| `argocd-dex-server` | SSO (not used here) |
| `argocd-applicationset-controller` | generates Applications from templates (not used here) |
| `argocd-notifications-controller` | notifications (not used here) |

## The config files, value by value

### `confs/argocd-app.yaml` — the Argo CD Application

An `Application` is one Argo CD "app": a pair of *where the YAML lives* (source) and *where it must run* (destination), plus the sync rules.

| Field | Value | Meaning |
|-------|-------|---------|
| `apiVersion` | `argoproj.io/v1alpha1` | API group of Argo CD's custom resources (installed with Argo CD). |
| `kind` | `Application` | The Argo CD resource type. |
| `metadata.name` | `playground` | Name of the Application: `kubectl get app playground -n argocd`. |
| `metadata.namespace` | `argocd` | Applications live in Argo CD's own namespace, **not** in `dev`. |
| `spec.project` | `default` | Built-in Argo CD project with no restrictions (any repo, any namespace). |
| `spec.source.repoURL` | `https://github.com/26TOXIC26/iot-gitops-amousaid` | The GitOps repo Argo CD clones. No credentials are configured, so it must be public. |
| `spec.source.targetRevision` | `HEAD` | Follow the latest commit of the repo's default branch (`main`). Could be a branch, tag or commit SHA to pin a version. |
| `spec.source.path` | `p3/manifests` | Folder inside the repo to deploy. Plain YAML files (no Helm/Kustomize). Relative to the repo root and case-sensitive. |
| `spec.destination.server` | `https://kubernetes.default.svc` | The in-cluster address of the Kubernetes API: "this same cluster", the one Argo CD runs in. |
| `spec.destination.namespace` | `dev` | Namespace the app is deployed into. |
| `spec.syncPolicy.automated` | *(present)* | Argo CD syncs by itself whenever Git and the cluster differ. No manual **Sync** click. |
| `…automated.prune` | `true` | A resource that is **removed from Git is deleted from the cluster** (delete the Service from the YAML and Argo CD deletes the Service). Without it, such resources would be left behind. It deletes resources, not the namespace. |
| `…automated.selfHeal` | `true` | If someone changes the live objects by hand (`kubectl edit`, `kubectl scale`…), Argo CD puts them back to what Git says. |
| `spec.syncPolicy.syncOptions` | `CreateNamespace=true` | Create the destination namespace if it is missing. A safety net: the script already creates `dev`. |

### `manifests/deployment.yaml` — what gets deployed

This file lives in the **GitOps repo** (`p3/manifests/deployment.yaml`), not in this folder: it is what Argo CD reads. One file, two Kubernetes objects separated by `---`. It is a *declaration of desired state*, not a program: Kubernetes keeps working until reality matches it.

**Deployment `wil-playground`** — declares how many Pods run and what they run.

| Field | Value | Meaning |
|-------|-------|---------|
| `apiVersion` / `kind` | `apps/v1` / `Deployment` | Object type. Creates a ReplicaSet, which creates the Pods; also provides rolling updates. |
| `metadata.name` | `wil-playground` | Pods are named `wil-playground-<hash>-<id>` (as in the subject's example). |
| `metadata.namespace` | `dev` | Where it lives. |
| `spec.replicas` | `1` | Run one Pod. |
| `spec.selector.matchLabels` | `app: playground` | How the Deployment recognizes the Pods it owns. **Must match** the Pod template's labels. |
| `spec.template.metadata.labels` | `app: playground` | Label stamped on every Pod. The Service uses it to find them. |
| `…containers[0].name` | `playground` | Container name inside the Pod. |
| `…containers[0].image` | `wil42/playground:v1` (or `:v2`) | Wil's image from Docker Hub. **The one line you change for the demo.** |
| `…containers[0].ports[0].containerPort` | `8888` | Port the app listens on. Informational only: it does not open or block anything. |

**Service `playground-svc`** — a stable address in front of the Pods.

| Field | Value | Meaning |
|-------|-------|---------|
| `apiVersion` / `kind` | `v1` / `Service` | The core API group has no name, hence just `v1`. |
| `metadata.name` / `namespace` | `playground-svc` / `dev` | Reachable inside the cluster as `playground-svc.dev.svc.cluster.local:8888`. |
| `spec.selector` | `app: playground` | Traffic goes to Pods carrying this label. |
| `spec.ports[0].port` | `8888` | The port the Service itself listens on. |
| `spec.ports[0].targetPort` | `8888` | The port on the Pod that traffic is forwarded to. |
| `spec.type` | `LoadBalancer` | Asks for an address outside the cluster. K3s's ServiceLB answers by opening port 8888 on the node, and k3d publishes it on the host (`--port "8888:8888@loadbalancer"`). Without this line the Service would be a `ClusterIP` (reachable only inside the cluster), and the app would need `kubectl port-forward`. |

How the pieces find each other — everything hangs on the label `app=playground`:

```
Deployment wil-playground ── owns ──► ReplicaSet ──► Pod   (label app=playground)
                                                      ▲
Service playground-svc ── selects pods with app=playground
```

When you change the image tag, the Pod template changes, so the Deployment starts a **new** ReplicaSet and does a rolling update. By default (25 % surge, 25 % unavailable) with one replica it starts the new Pod first and removes the old one only after the new one is Ready, so for a short moment you will see **two** Pods.

## Using the lab

### Check the state

```bash
kubectl get nodes
kubectl get ns
kubectl get pods -n argocd
kubectl get app -n argocd              # Argo CD's view of the app
kubectl get all -n dev                 # what Argo CD deployed
```

`kubectl get app` shows two statuses:

| Status | Values | Meaning |
|--------|--------|---------|
| SYNC STATUS | `Synced` / `OutOfSync` / `Unknown` | Does the cluster match Git? `Unknown` means Argo CD could not compare (for example a repo or path error). |
| HEALTH STATUS | `Healthy` / `Progressing` / `Degraded` / `Missing` | Are the deployed objects actually working? `Progressing` while a rollout runs, `Degraded` for example on `ImagePullBackOff`. |

### Open the Argo CD UI

```bash
# initial admin password (generated at install)
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo

# tunnel the UI. Use 8081, not 8080: host port 8080 is already taken by the k3d load balancer
kubectl port-forward svc/argocd-server -n argocd 8081:443
```

Browse to <https://localhost:8081> (self-signed certificate: accept the warning) and log in as `admin`. The `argocd` CLI is not installed by the script; everything here uses `kubectl` and the web UI.

### Reach the app

```bash
curl http://localhost:8888/                                    # {"status":"ok", "message": "v1"}
```

The app listens on 8888 and answers with a small JSON whose `message` is its version (`v1` or `v2`). Host port 8888 is published by the k3d load balancer for the `LoadBalancer` Service, so there is no tunnel to start. If `curl` is refused right after `setup.sh`, the Pod is still starting: `kubectl get pods -n dev`.

### Demo: change the version through Git

This is what the evaluator asks you to do.

```bash
# 1. In a clone of the GitOps repo (needs push rights)
git clone https://github.com/26TOXIC26/iot-gitops-amousaid.git && cd iot-gitops-amousaid
sed -i 's#wil42/playground:v1#wil42/playground:v2#' p3/manifests/deployment.yaml
git commit -am "v2" && git push

# 2. Argo CD notices within about 3 minutes. To not wait, ask for a refresh:
kubectl annotate app playground -n argocd argocd.argoproj.io/refresh=hard --overwrite

# 3. Watch the rollout (Ctrl+C to stop): the v2 Pod starts, the v1 Pod terminates
kubectl get pods -n dev -w
kubectl get app -n argocd              # back to Synced / Healthy
```

Then run the same `curl http://localhost:8888/` again: it must now say `"message": "v2"`. Nothing to restart: the Service follows the new Pod by its label.

To go back to v1, repeat with the two tags swapped.

### Optional: watch self-heal work

```bash
kubectl scale deployment wil-playground -n dev --replicas=3    # a manual change
kubectl get pods -n dev -w                                     # Argo CD puts it back to 1
```

The change you made by hand disagrees with Git, so Argo CD reverts it. Moral: change the app by editing the GitOps repo, never with `kubectl` in `dev`.

## Defense checklist

Maps to the subject (Part 3 and the submission chapter).

- [ ] The folder at the repo root is named exactly `p3` (lowercase) and contains `scripts/` and `confs/`. Folder and file names are checked.
- [ ] The install script sets up everything on a clean VM (the subject asks for it to be run **during the defense**, on your machine, with your internet).
- [ ] The GitOps repo is **public** (open it in a private browser window) and its name contains a group member's login.
- [ ] Two namespaces exist: `kubectl get ns` shows `argocd` and `dev`.
- [ ] The app runs in `dev`: `kubectl get pods -n dev` shows `wil-playground-…  1/1  Running`.
- [ ] Argo CD UI shows `playground` as **Synced** and **Healthy**.
- [ ] **Before starting:** the GitOps repo is at `v1` (see [Which version is deployed?](#which-version-is-deployed)); `curl` shows `"message": "v1"`.
- [ ] **Live:** change the tag in GitHub, Argo CD syncs, the same `curl` shows `"message": "v2"`.
- [ ] Be ready to explain: K3s vs K3d ([below](#k3s-vs-k3d)), what Argo CD does and why "pull", what a Namespace / Deployment / Service is, and what `prune` and `selfHeal` do.
- [ ] Namespace vs Pod: a **Namespace** is a named partition of the cluster (it groups and isolates objects: `argocd`, `dev`); a **Pod** is the smallest runnable unit (one or more containers). Pods live *inside* a namespace: `kubectl get pods -n dev`.

## K3s vs K3d

| | K3s | K3d |
|---|-----|-----|
| What it is | A lightweight Kubernetes distribution (one small binary) | A CLI that runs K3s **inside Docker containers** |
| Runs on | A machine or VM | Docker: every node is a container |
| Used in | Parts 1 and 2 (on Vagrant VMs) | Part 3 (no Vagrant) |
| Good for | Real, low-resource clusters | Disposable multi-node clusters on one machine, created in seconds |

## Troubleshooting

| Symptom | Likely cause | What to do |
|---------|--------------|------------|
| Nothing in `dev` after several minutes | Argo CD cannot sync. | `kubectl get app -n argocd`, then `kubectl logs -n argocd deploy/argocd-repo-server --tail=50` and `kubectl logs -n argocd statefulset/argocd-application-controller --tail=50`. |
| `curl localhost:8888` refuses or returns nothing | The Pod is not Ready yet, or the cluster was created without host port 8888 (older script). | `kubectl get pods -n dev`; check `docker port k3d-iotcluster-serverlb`; run `sudo bash scripts/setup.sh` again (it adds the port to an existing cluster). |
| `permission denied` on `/var/run/docker.sock` when running `docker`/`k3d` | Your user is not in the `docker` group. | Use `sudo`, or `sudo usermod -aG docker $USER` and log in again. |
| `kubectl` says there is no config or connection refused | The script writes `~/.kube/config` only when run through `sudo` by a non-root user. | `k3d kubeconfig merge iotcluster --kubeconfig-merge-default --kubeconfig-switch-context` (merges instead of overwriting). |

## Reset and cleanup

```bash
k3d cluster delete iotcluster          # removes the node containers and the kubeconfig entry (add sudo if your user is not in the docker group)
sudo bash scripts/setup.sh             # rebuild from scratch
```

Docker, `kubectl` and k3d stay installed; the script reuses them when they are already there.

## Known limitations

- **Switches your current `kubectl` context** to `k3d-iotcluster`. The user's `~/.kube/config` is merged (other clusters stay), not overwritten; use `kubectl config use-context` to go back.
- **Debian/Ubuntu and amd64 only.**
- **Nothing is version-pinned:** `kubectl` is "latest stable", k3d is the latest release, Argo CD comes from the moving `stable` manifest, and Docker is whatever `docker.io` your distro ships. A future upstream release can change behavior. To pin: set `TAG=…` for the k3d installer and use a versioned Argo CD URL (`…/argo-cd/<version>/manifests/install.yaml`).
- **No checksum or signature checks** on downloaded binaries, and the k3d installer is piped to `bash`. Fine for a lab, not for production.
- **The GitOps repo must be public.** No repository credentials are configured in Argo CD.
- **Polling, not webhooks.** Argo CD notices a push within about 3 minutes unless you trigger a refresh.
- **Host port 8080 is mapped but unused.** There is no Ingress; the app is published on host port 8888 by its `LoadBalancer` Service instead.
- **The app port is public on the host.** `8888` is published on all interfaces (`0.0.0.0`), so anyone on the same network can reach the app. Fine for a lab.
- **Argo CD itself is installed imperatively** by the script. Only the `dev` app is managed by GitOps.

## References

- Subject: `../subject.pdf`, section *IV.3 Part 3: K3d and Argo CD*.
- Diagram: [`../K8S.drawio`](../K8S.drawio), page *P3 GitOps Flow (Argo CD)*.
- The app: <https://hub.docker.com/r/wil42/playground> (port 8888, tags `v1` and `v2`).
- k3d: <https://k3d.io/> · K3s: <https://k3s.io/>
- Argo CD docs: <https://argo-cd.readthedocs.io/en/stable/>
- Kubernetes docs: <https://kubernetes.io/docs/home/>
