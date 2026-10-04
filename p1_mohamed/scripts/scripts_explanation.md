# 📘 Explanation of `server.sh` and `worker.sh`

> These two scripts are part of a **Kubernetes (K3s)** cluster setup using **Vagrant**.
> The **server** is the "brain" (master/control-plane) of the cluster.
> The **worker** is the "muscle" — it receives tasks from the server and runs them.

---

## 🖥️ `server.sh` — Sets up the Kubernetes Master Node

```bash
#!/bin/bash
```
**What it is:** This is called a **shebang** line. It always goes on line 1.
**What it does:** Tells the OS *which program* should run this script. `/bin/bash` means "use the Bash shell to execute every line below."
Without this line, the OS wouldn't know how to interpret the script.

---

```bash
set -e
```
**What it is:** A Bash "option" that changes how errors are handled.
**What it does:** If **any** command in the script fails (returns an error), the **entire script stops immediately** instead of continuing. This prevents silent failures — imagine installing software and halfway through a command fails, but the script keeps going and creates a broken setup. `set -e` prevents that.

---

```bash
SERVER_IP="192.168.56.110"
```
**What it is:** Creating a **variable**. Think of a variable as a labeled box that holds a value.
**What it does:** Creates a variable named `SERVER_IP` and stores the string `"192.168.56.110"` (the IP address of the server VM) inside it. Later, whenever the script needs to use this IP, it just says `$SERVER_IP` instead of typing the full address every time.

---

```bash
IFACE=$(ip -o -4 addr show to "$SERVER_IP" | awk '{print $2}')
```
**What it is:** A variable assignment using **command substitution** (`$(...)`) and a **pipe** (`|`).
**What it does (step by step):**

1. `ip -o -4 addr show to "$SERVER_IP"` — Runs the `ip` command to list all **network interfaces** (like ethernet cards) that have the IP address `192.168.56.110`. The `-o` flag means "one line per result" and `-4` means "only IPv4 addresses."
2. `|` (pipe) — Takes the output of the command on the left and sends it as **input** to the command on the right.
3. `awk '{print $2}'` — `awk` is a text-processing tool. `{print $2}` means "print only the **second word** of each line." That second word is the network interface name (e.g., `eth1`).
4. The whole result is stored in the `IFACE` variable.

**In simple terms:** "Find out which network card on this machine has the IP `192.168.56.110`, and save its name."

---

```bash
rm -f /vagrant/token
```
**What it is:** The `rm` (remove) command with the `-f` flag.
**What it does:** Deletes the file `/vagrant/token` if it exists. The `-f` flag means **"force"** — don't show an error if the file doesn't exist, just silently succeed.
**Why:** This is a cleanup step. The token file is how the server communicates a secret key to the worker. Deleting it first ensures we start fresh with a new token each time.

---

```bash
curl -sfL https://get.k3s.io | \
    INSTALL_K3S_EXEC="server \
        --node-ip=${SERVER_IP} \
        --advertise-address=${SERVER_IP} \
        --flannel-iface=${IFACE} \
        --disable=traefik \
        --disable=metrics-server \
        --disable=servicelb \
        --disable=local-storage \
        --write-kubeconfig-mode=644" \
    sh -
```
**What it is:** The main installation command. This is one long command split across multiple lines using `\` (backslash = "line continues below").
**What it does (piece by piece):**

- `curl -sfL https://get.k3s.io` — Downloads the K3s installation script from the internet.
  - `-s` = silent (no progress bar)
  - `-f` = fail if the download fails (don't silently get an error page)
  - `-L` = follow redirects (if the URL moves, follow it)
- `|` — Pipes the downloaded script into the next command.
- `INSTALL_K3S_EXEC="server ..."` — Sets a temporary **environment variable** that tells the installer *what options* to use. It's not saved permanently.
- `sh -` — Runs the downloaded script using the `sh` shell. The `-` at the end means "read the script from stdin (from the pipe)."

**The options inside `INSTALL_K3S_EXEC`:**

| Option | Meaning |
|--------|---------|
| `server` | Install K3s in **server (master) mode** |
| `--node-ip=${SERVER_IP}` | Tell K3s this node's IP is `192.168.56.110` |
| `--advertise-address=${SERVER_IP}` | Tell other nodes to reach this server at `192.168.56.110` |
| `--flannel-iface=${IFACE}` | Use the specific network card (`IFACE`) for internal cluster traffic |
| `--disable=traefik` | Don't install Traefik (a built-in load balancer) |
| `--disable=metrics-server` | Don't install the metrics server |
| `--disable=servicelb` | Don't install the built-in load balancer |
| `--disable=local-storage` | Don't install local storage provisioner |
| `--write-kubeconfig-mode=644` | Make the config file readable by all users (not just root) |

---

```bash
while [ ! -f /var/lib/rancher/k3s/server/node-token ]; do
    sleep 1
done
```
**What it is:** A **while loop** — keeps repeating until a condition is false.
**What it does:**
- `[ ! -f /var/lib/rancher/k3s/server/node-token ]` — Checks if the file `node-token` does **NOT** exist (`!` means "not", `-f` means "is a file").
- As long as the file **doesn't exist**, the loop runs.
- `sleep 1` — Waits 1 second before checking again.

**In simple terms:** "Keep waiting (checking every second) until K3s has finished starting up and created its token file."

---

```bash
cp /var/lib/rancher/k3s/server/node-token /vagrant/token
```
**What it is:** The `cp` (copy) command.
**What it does:** Copies the K3s token file to `/vagrant/token`. The `/vagrant/` folder is a **shared folder** between the server VM and the worker VM (it's a Vagrant feature). This is how the worker will get the token it needs to join the cluster.

---

```bash
chmod 644 /vagrant/token
```
**What it is:** The `chmod` (change mode) command — changes file permissions.
**What it does:** Sets the permissions of the token file to `644`.
- `6` (owner) = read + write
- `4` (group) = read only
- `4` (others) = read only

**In simple terms:** "Let everyone read this file, but only the owner can edit it."

---

```bash
mkdir -p /home/vagrant/.kube
```
**What it is:** `mkdir` (make directory) with the `-p` flag.
**What it does:** Creates the directory `/home/vagrant/.kube`.
- `-p` means **"create parent directories too if they don't exist"** and **"don't error if the directory already exists."**

---

```bash
cp /etc/rancher/k3s/k3s.yaml /home/vagrant/.kube/config
```
**What it does:** Copies the K3s **kubeconfig** file to the standard location where `kubectl` (the Kubernetes CLI tool) looks for configuration. This allows the `vagrant` user to run `kubectl` commands to manage the cluster.

---

```bash
chown -R vagrant:vagrant /home/vagrant/.kube
```
**What it is:** `chown` (change owner) with the `-R` flag.
**What it does:** Changes the **owner** of the `.kube` directory and everything inside it to `vagrant` (user) and `vagrant` (group).
- `-R` = recursive (apply to all files and subdirectories inside)

**Why:** The directory was created as `root`, but the `vagrant` user needs to own it to use it freely.

---

```bash
cat << 'EOF' > /usr/local/bin/k
#!/bin/bash
exec /usr/local/bin/k3s kubectl "$@"
EOF
```
**What it is:** A **heredoc** (`<< 'EOF'`) — a way to write a multi-line string directly in a script.
**What it does:** Creates a new file at `/usr/local/bin/k` with these exact contents:
```bash
#!/bin/bash
exec /usr/local/bin/k3s kubectl "$@"
```
- `cat << 'EOF'` — Start reading text until we see the word `EOF` alone on a line.
- `> /usr/local/bin/k` — Write that text into the file `/usr/local/bin/k`.
- Inside the file: `exec /usr/local/bin/k3s kubectl "$@"` means "when this `k` script is called, run `k3s kubectl` and pass along ALL arguments (`$@`) that were given."

**In simple terms:** Creates a shortcut script `k` that is equivalent to typing `kubectl`.

---

```bash
chmod +x /usr/local/bin/k
```
**What it does:** Makes the `k` script **executable** (runnable as a program).
- `+x` means "add execute permission."

---

```bash
echo "alias k='kubectl'" >> /home/vagrant/.bashrc
echo "alias k='kubectl'" >> /root/.bashrc
```
**What it is:** `echo` prints text. `>>` **appends** text to a file (adds to the end without deleting existing content).
**What it does:** Adds the line `alias k='kubectl'` to the `.bashrc` file of both the `vagrant` user and `root`.
- `.bashrc` is a file that runs automatically every time a user opens a terminal.
- `alias k='kubectl'` means "whenever I type `k`, pretend I typed `kubectl`."

**Result:** After opening a new terminal, you can type `k get pods` instead of `kubectl get pods`.

---
---

## ⚙️ `worker.sh` — Sets up the Kubernetes Worker Node

```bash
#!/bin/bash
```
Same as server.sh — tells the OS to use Bash to run this script.

---

```bash
set -e
```
Same as server.sh — stop the script immediately if any command fails.

---

```bash
SERVER_IP="192.168.56.110"
```
Stores the **server's IP address** in a variable. The worker needs to know where the server is so it can connect to it.

---

```bash
WORKER_IP="192.168.56.111"
```
Stores **this worker's own IP address** in a variable. This is used later to tell K3s what IP address to use for this node.

---

```bash
IFACE=$(ip -o -4 addr show to "$WORKER_IP" | awk '{print $2}')
```
Same logic as in `server.sh`, but this time it looks up the network interface that has the **worker's IP** (`192.168.56.111`) instead of the server's IP.

**Result:** `IFACE` will hold the name of the network card the worker should use for cluster communication (e.g., `eth1`).

---

```bash
while [ ! -f /vagrant/token ]; do
    sleep 1
done
```
**What it does:** Waits in a loop until the file `/vagrant/token` exists.
**Why:** Remember that the server copies its token to `/vagrant/token`. The worker must **wait** for the server to finish starting up and create that token before it can join the cluster. This loop keeps checking every second until the file appears.

---

```bash
TOKEN=$(cat /vagrant/token)
```
**What it is:** Command substitution — runs a command and stores its output in a variable.
**What it does:**
- `cat /vagrant/token` — reads and prints the contents of the token file.
- The output (the token string) is stored in the `TOKEN` variable.

---

```bash
curl -sfL https://get.k3s.io | \
    K3S_URL="https://${SERVER_IP}:6443" \
    K3S_TOKEN="${TOKEN}" \
    INSTALL_K3S_EXEC="agent --node-ip=${WORKER_IP} --flannel-iface=${IFACE}" \
    sh -
```
**What it does:** Downloads and runs the K3s installer — this time in **agent (worker) mode**.

**The pieces:**
- `curl -sfL https://get.k3s.io` — Downloads the K3s install script (same as server).
- `|` — Pipes it to `sh -` to execute it.
- `K3S_URL="https://${SERVER_IP}:6443"` — Tells K3s where the **master server** is. Port `6443` is the default Kubernetes API port.
- `K3S_TOKEN="${TOKEN}"` — Provides the **secret token** so the server trusts this worker and allows it to join.
- `INSTALL_K3S_EXEC="agent ..."` — Installs K3s in **agent mode** (worker, not master).
  - `--node-ip=${WORKER_IP}` — Sets this node's IP to `192.168.56.111`.
  - `--flannel-iface=${IFACE}` — Uses the correct network interface for cluster networking.

---

```bash
echo "alias k='kubectl'" >> /home/vagrant/.bashrc
```
Same as in `server.sh` — adds a shortcut so the vagrant user can type `k` instead of `kubectl` in the terminal.

> **Note:** The worker only adds the alias for the `vagrant` user, not `root`. The server script adds it for both.

---

## 🗺️ Big Picture: How the Two Scripts Work Together

```
server.sh                         /vagrant/token            worker.sh
   |                             (shared folder)               |
   |-- Install K3s (server mode)                               |
   |-- Wait for node-token...                                  |-- Wait for token file...
   |-- Copy token ------------>  [token written]               |
   |                                                 [token found!]
   |                                                           |-- Read token
   |                                                           |-- Install K3s (agent mode)
   |                                                           |-- Join the cluster
```

**The shared `/vagrant/` folder** is the secret communication channel between server and worker.
The server writes the token there, and the worker reads it.
Both scripts use `while` loops to perfectly synchronize their timing.

---

## 🧠 Quick Reference — Core Bash Concepts Used

| Concept | Example | What it means |
|---|---|---|
| **Shebang** | `#!/bin/bash` | "Use Bash to run this file" |
| **`set -e`** | `set -e` | "Crash immediately if any command fails" |
| **Variable** | `SERVER_IP="192.168.56.110"` | A named box that holds a value |
| **Using a variable** | `$SERVER_IP` or `${SERVER_IP}` | Read what's inside the box |
| **Command substitution** | `X=$(some command)` | Run a command and store its output |
| **Pipe** | `cmd1 \| cmd2` | Send output of `cmd1` as input to `cmd2` |
| **While loop** | `while [ condition ]; do ... done` | Keep repeating until condition is false |
| **Heredoc** | `cat << 'EOF' > file` | Write multi-line text into a file |
| **`>>`** | `echo "text" >> file` | Append text to a file (don't overwrite) |
| **`chmod +x`** | `chmod +x script.sh` | Make a file executable (runnable) |
| **`chown`** | `chown user:group file` | Change who owns a file |
