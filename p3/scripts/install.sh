#!/usr/bin/env bash

set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
  SUDO=()
else
  SUDO=(sudo)
fi

"${SUDO[@]}" apt-get update
"${SUDO[@]}" apt-get install -y ca-certificates curl docker.io
"${SUDO[@]}" systemctl enable --now docker

if ! command -v kubectl >/dev/null 2>&1; then
  KUBECTL_VERSION="$(curl -LfsS https://dl.k8s.io/release/stable.txt)"
  curl -LfsS -o /tmp/kubectl \
    "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
  "${SUDO[@]}" install -m 0755 /tmp/kubectl /usr/local/bin/kubectl
  rm -f /tmp/kubectl
fi

if ! command -v k3d >/dev/null 2>&1; then
  curl -LfsS https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
fi

LOGIN_USER="${SUDO_USER:-${USER:-$(id -un)}}"
if [ "$(id -u)" -ne 0 ] && ! id -nG "$LOGIN_USER" | tr ' ' '\n' | grep -qx docker; then
  "${SUDO[@]}" usermod -aG docker "$LOGIN_USER"
  echo "Docker group added. Log out and back in, then run setup.sh."
fi

docker --version
kubectl version --client
k3d version

