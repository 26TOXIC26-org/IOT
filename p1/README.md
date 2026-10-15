# Inception of Things (IoT) — Part 1

## 1. Présentation du projet

La première partie du projet **Inception of Things** consiste à mettre en place une infrastructure virtualisée composée de deux machines virtuelles Debian, puis à déployer un cluster Kubernetes léger avec K3s.

Le cluster est constitué de :

- Un nœud **K3s Server**, qui joue le rôle de control plane.
- Un nœud **K3s Agent**, qui rejoint le serveur en tant que worker.

La création et la configuration des machines virtuelles sont réalisées avec **Vagrant** et **VirtualBox**.

## 2. Architecture

```text
                    Host Machine
                         |
                    VirtualBox
                         |
                  Debian VM (iot)
                         |
                       Vagrant
                         |
          +--------------+--------------+
          |                             |
     khmessahS                    khmessahSW
     K3s Server                   K3s Agent
          |                             |
   192.168.56.110              192.168.56.111
          |                             |
          +---------- K3s --------------+
                    Cluster
```

### Configuration des machines

| Paramètre  | Server         | Agent          |
| ---------- | -------------- | -------------- |
| Nom        | khmessahS      | khmessahSW     |
| Système    | Debian         | Debian         |
| CPU        | 1              | 1              |
| RAM        | 1024 MB        | 1024 MB        |
| Adresse IP | 192.168.56.110 | 192.168.56.111 |
| Rôle       | Control Plane  | Worker         |
| Kubernetes | K3s Server     | K3s Agent      |

## 3. Environnement utilisé

- VirtualBox
- Vagrant
- Debian
- K3s
- kubectl
- SSH
- Réseau privé VirtualBox

## 4. Structure du projet

```text
iot/
└── p1/
    ├── Vagrantfile
    ├── README.md
    ├── scripts/
    └── confs/
```

- `Vagrantfile` : définition et configuration des machines virtuelles.
- `scripts/` : scripts d'installation et de configuration éventuels.
- `confs/` : fichiers de configuration éventuels.
- `README.md` : documentation de la partie 1.

## 5. Création des machines virtuelles

### 5.1 Initialisation du projet

Depuis la machine Debian principale :

```bash
mkdir -p ~/Desktop/iot/p1
cd ~/Desktop/iot/p1

mkdir -p scripts confs
```

### 5.2 Configuration du Vagrantfile

Le fichier `Vagrantfile` définit les deux machines virtuelles.

```ruby
Vagrant.configure("2") do |config|

  config.vm.box = "debian/testing64"

  config.vm.define "khmessahS" do |server|

    server.vm.hostname = "khmessahS"

    server.vm.network "private_network",
      ip: "192.168.56.110"

    server.vm.provider "virtualbox" do |vb|
      vb.gui = true
      vb.memory = "1024"
      vb.cpus = 1
    end

  end

  config.vm.define "khmessahSW" do |worker|

    worker.vm.hostname = "khmessahSW"

    worker.vm.network "private_network",
      ip: "192.168.56.111"

    worker.vm.provider "virtualbox" do |vb|
      vb.gui = true
      vb.memory = "1024"
      vb.cpus = 1
    end

  end

end
```

**Remarque :** la box utilisée dans la configuration est `debian/testing64`. Elle correspond à Debian Testing et non à une version stable. Si la consigne exige strictement la dernière version stable, ce point doit être harmonisé avant la validation finale.

### 5.3 Démarrage des VMs

```bash
vagrant up
```

Afficher les machines :

```bash
vagrant status
```

Se connecter au serveur :

```bash
vagrant ssh khmessahS
```

Se connecter au worker :

```bash
vagrant ssh khmessahSW
```

## 6. Configuration réseau

Les deux machines utilisent un réseau privé avec des adresses IP statiques.

| Machine    | Adresse IP     |
| ---------- | -------------- |
| khmessahS  | 192.168.56.110 |
| khmessahSW | 192.168.56.111 |

### Vérification des adresses IP

Sur le serveur :

```bash
ip -4 addr
```

Sur le worker :

```bash
ip -4 addr
```

Vérifier la communication entre les deux machines :

```bash
ping -c 4 192.168.56.111
```

Depuis le worker :

```bash
ping -c 4 192.168.56.110
```

## 7. Configuration SSH

L'objectif est de permettre une connexion SSH sans saisie de mot de passe entre les deux machines.

### 7.1 Génération de la clé SSH

Sur le serveur :

```bash
ssh-keygen -t ed25519
```

Valider les choix proposés pour générer la clé.

### 7.2 Copie de la clé publique

```bash
ssh-copy-id vagrant@192.168.56.111
```

### 7.3 Vérification

```bash
ssh vagrant@192.168.56.111
```

La connexion SSH a été testée entre les deux machines.

## 8. Installation de K3s Server

Le serveur K3s est installé sur la machine :

```text
khmessahS
192.168.56.110
```

### 8.1 Installation

Sur le serveur :

```bash
curl -sfL https://get.k3s.io | sh -
```

### 8.2 Configuration de l'adresse IP du serveur

Lors de la configuration initiale, K3s utilisait l'adresse NAT `10.0.2.15`.

Pour utiliser l'adresse IP privée prévue dans le projet, le fichier de configuration suivant a été créé :

```bash
sudo mkdir -p /etc/rancher/k3s
sudo nano /etc/rancher/k3s/config.yaml
```

Contenu :

```yaml
node-ip: 192.168.56.110
advertise-address: 192.168.56.110
```

Cette configuration permet au serveur K3s d'utiliser l'adresse IP privée pour son identification et l'annonce de son adresse.

### 8.3 Redémarrage du service

```bash
sudo systemctl restart k3s
```

Vérifier le service :

```bash
sudo systemctl status k3s
```

### 8.4 Vérification de l'installation

```bash
sudo k3s --version
```

Récupérer le token d'authentification du serveur :

```bash
sudo cat /var/lib/rancher/k3s/server/node-token
```

Ce token permet à l'agent de rejoindre le cluster. Il doit rester privé et ne doit pas être publié dans le dépôt Git.

## 9. Installation de K3s Agent

Le worker est configuré sur :

```text
khmessahSW
192.168.56.111
```

### 9.1 Configuration de l'adresse IP du worker

Sur le worker :

```bash
sudo mkdir -p /etc/rancher/k3s
sudo nano /etc/rancher/k3s/config.yaml
```

Contenu :

```yaml
node-ip: 192.168.56.111
```

### 9.2 Installation de l'agent

Sur le worker, définir les informations de connexion au serveur :

```bash
export K3S_URL="https://192.168.56.110:6443"
export K3S_TOKEN="<TOKEN_DU_SERVEUR>"
```

Puis lancer l'installation :

```bash
curl -sfL https://get.k3s.io | sh -
```

Remplacer `<TOKEN_DU_SERVEUR>` par le token récupéré sur le serveur.

### 9.3 Vérification du service Agent

```bash
sudo systemctl status k3s-agent
```

## 10. Installation et utilisation de kubectl

K3s intègre kubectl dans sa commande `k3s kubectl`.

Pour utiliser directement `kubectl` sur le serveur :

```bash
sudo ln -s /usr/local/bin/k3s /usr/local/bin/kubectl
```

Vérifier la version :

```bash
kubectl version --client
```

Si la commande nécessite les droits root pour accéder à la configuration du cluster :

```bash
sudo kubectl get nodes
```

## 11. Vérification du cluster Kubernetes

Depuis le serveur :

### 11.1 Vérifier les nœuds

```bash
sudo kubectl get nodes -o wide
```

Résultat attendu :

```text
NAME          STATUS   ROLES
khmessahs     Ready    control-plane
khmessahsw    Ready    <none>
```

Les deux nœuds doivent être à l'état `Ready`.

### 11.2 Vérifier les composants système

```bash
sudo kubectl get pods -A
```

Les composants observés lors de la vérification comprennent :

- CoreDNS
- Local Path Provisioner
- Metrics Server
- Traefik
- Service LoadBalancer de Traefik

Les pods système ont été vérifiés à l'état `Running`, et les jobs d'installation concernés à l'état `Completed`.

### 11.3 Vérifier les services

```bash
sudo kubectl get services -A
```

### 11.4 Vérifier les informations du cluster

```bash
sudo kubectl cluster-info
```

## 12. Problèmes rencontrés et solutions

### Problème 1 : mauvaise adresse IP utilisée par K3s

**Problème :**

K3s utilisait l'adresse NAT de la machine virtuelle :

```text
10.0.2.15
```

Au lieu de l'adresse privée attendue :

```text
192.168.56.110
```

**Solution :**

Configuration de l'adresse IP dans :

```text
/etc/rancher/k3s/config.yaml
```

Puis redémarrage du service :

```bash
sudo systemctl restart k3s
```

### Problème 2 : communication avec l'API Kubernetes

Des délais d'attente ont été rencontrés lors de certaines requêtes à l'API Kubernetes.

Le service K3s a été redémarré, puis les vérifications des nœuds et des pods ont été effectuées.

Commandes de diagnostic :

```bash
sudo systemctl status k3s
sudo journalctl -u k3s -n 100 --no-pager
sudo kubectl get nodes
```

## 13. Commandes utiles pour la gestion des VMs

Depuis le répertoire `p1` :

| Commande                 | Description             |
| ------------------------ | ----------------------- |
| `vagrant up`             | Démarrer les VMs        |
| `vagrant status`         | Afficher leur état      |
| `vagrant halt`           | Arrêter les VMs         |
| `vagrant reload`         | Redémarrer les VMs      |
| `vagrant ssh khmessahS`  | Se connecter au serveur |
| `vagrant ssh khmessahSW` | Se connecter au worker  |
| `vagrant suspend`        | Suspendre les VMs       |
| `vagrant resume`         | Reprendre les VMs       |

Attention : `vagrant destroy` supprime les machines virtuelles et peut entraîner la perte de leurs données.

## 14. Résultat de la partie 1

La partie 1 a permis de réaliser les opérations suivantes :

- [x] Création de deux machines virtuelles avec Vagrant.
- [x] Configuration des ressources CPU et RAM.
- [x] Attribution des adresses IP privées.
- [x] Configuration des hostnames.
- [x] Test de communication réseau.
- [x] Configuration SSH sans mot de passe.
- [x] Installation de K3s Server.
- [x] Installation de K3s Agent.
- [x] Configuration des adresses IP des nœuds K3s.
- [x] Vérification de l'installation de kubectl.
- [x] Vérification des deux nœuds Kubernetes.
- [x] Vérification des pods système.
- [x] Vérification finale de la conformité de la distribution Debian avec la consigne.

## 15. Conclusion

La première partie du projet Inception of Things a permis de mettre en place un environnement virtualisé avec deux machines Debian et un cluster Kubernetes léger basé sur K3s.

Le serveur et le worker communiquent via leurs adresses IP privées, et les deux nœuds ont été observés à l'état `Ready`.

Cette infrastructure constitue la base pour les parties suivantes du projet.
