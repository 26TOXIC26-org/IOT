# 🚀 Inception of Things — Part 1 (p1_mohamed)

> **42 School | IoT Project**  
> Automated K3s Kubernetes cluster provisioning using Vagrant and VirtualBox.

---

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
- [Network Configuration](#network-configuration)
- [Provisioning Scripts](#provisioning-scripts)
- [Usage](#usage)
- [Project Structure](#project-structure)

---

## Overview

This project automates the setup of a lightweight **K3s Kubernetes cluster** consisting of two virtual machines — a **server (master/control-plane)** node and a **worker (agent)** node — using **Vagrant** and **VirtualBox**.

The goal is to demonstrate infrastructure-as-code principles by provisioning a fully functional Kubernetes environment with a single command, without any manual configuration.

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                  Host Machine                        │
│                                                     │
│  ┌──────────────────────┐  ┌──────────────────────┐ │
│  │   mmondads (Server)  │  │  mmondadsw (Worker)  │ │
│  │   192.168.56.110     │◄─┤   192.168.56.111     │ │
│  │   K3s Control Plane  │  │   K3s Agent Node     │ │
│  │   1 CPU / 1024 MB    │  │   1 CPU / 1024 MB    │ │
│  └──────────────────────┘  └──────────────────────┘ │
│         Ubuntu 22.04 (Jammy) — Private Network       │
└─────────────────────────────────────────────────────┘
```

The two VMs communicate over a **host-only private network**. The server shares its join token via a Vagrant synced folder (`/vagrant/`), which the worker reads to securely join the cluster.

---

## Prerequisites

Make sure the following tools are installed on your host machine before proceeding:

| Tool | Version | Purpose |
|------|---------|---------|
| [Vagrant](https://www.vagrantup.com/) | ≥ 2.3 | VM lifecycle management |
| [VirtualBox](https://www.virtualbox.org/) | ≥ 6.1 | Virtualization provider |

---

## Getting Started

**Clone the repository and spin up the cluster:**

```bash
# 1. Navigate to the project directory
cd p1_mohamed

# 2. Start and provision both VMs
vagrant up

# 3. (Optional) SSH into either machine
vagrant ssh mmondads   # Server node
vagrant ssh mmondadsw  # Worker node
```

> ⚠️ **First run** downloads the `ubuntu/jammy64` Vagrant box and installs K3s on both VMs. This may take a few minutes depending on your internet connection.

---

## Network Configuration

| VM Name | Role | IP Address | Port |
|---------|------|-----------|------|
| `mmondads` | K3s Server (Control Plane) | `192.168.56.110` | `6443` (API) |
| `mmondadsw` | K3s Worker (Agent) | `192.168.56.111` | — |

Both VMs are connected via a **VirtualBox host-only private network**, isolated from the public internet.

---

## Provisioning Scripts

### `scripts/server.sh` — Control Plane Setup

Installs and configures the **K3s server** node:

- Detects the correct network interface for the private IP
- Cleans up any stale join token
- Installs K3s in **server mode** with the following components disabled for a minimal footprint:
  - `traefik` — Ingress controller
  - `metrics-server` — Resource metrics
  - `servicelb` — Built-in load balancer
  - `local-storage` — Local storage provisioner
- Waits for K3s to generate the join token, then copies it to the shared `/vagrant/token` file
- Sets up `kubectl` access for the `vagrant` user (`~/.kube/config`)
- Creates a `k` shortcut binary as an alias for `k3s kubectl`

### `scripts/worker.sh` — Agent Node Setup

Installs and configures the **K3s worker** node:

- Waits (polls every second) until the server's join token is available at `/vagrant/token`
- Reads the token and installs K3s in **agent mode**, connecting to the server at `https://192.168.56.110:6443`
- Configures the correct flannel network interface for internal cluster traffic

---

## Usage

After `vagrant up` completes, SSH into the server and interact with the cluster:

```bash
vagrant ssh mmondads

# Check cluster node status
kubectl get nodes
# or use the shortcut alias
k get nodes
```

Expected output:

```
NAME         STATUS   ROLES                  AGE   VERSION
mmondads     Ready    control-plane,master   Xm    v1.x.x+k3s1
mmondadsw    Ready    <none>                 Xm    v1.x.x+k3s1
```

**Common Vagrant commands:**

```bash
vagrant status          # Check VM states
vagrant halt            # Gracefully shut down VMs
vagrant destroy -f      # Delete all VMs
vagrant reload          # Restart VMs (re-reads Vagrantfile)
vagrant provision       # Re-run provisioning scripts
```

---

## Project Structure

```
p1_mohamed/
├── Vagrantfile                   # Defines both VMs (server + worker)
├── scripts/
│   ├── server.sh                 # Server provisioning script
│   ├── worker.sh                 # Worker provisioning script
│   └── scripts_explanation.md   # Detailed line-by-line script documentation
└── README.md                     # This file
```

---

<div align="center">
  Made with ☕ at <strong>42 School</strong>
</div>
