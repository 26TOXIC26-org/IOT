# Partie 1 — Vagrant et K3s

## Introduction

La première partie du projet **Inception of Things (IoT)** consiste à mettre en place un environnement Kubernetes léger à l'aide de **Vagrant** et **K3s**.

L'objectif est de créer deux machines virtuelles qui formeront un cluster K3s. La première machine fonctionnera comme **K3s Server (Controller)** et la deuxième comme **K3s Agent (ServerWorker)**.

Dans mon environnement de travail, le projet est réalisé à l'intérieur d'une machine virtuelle Debian. **VirtualBox** est utilisé pour exécuter cette machine Debian, puis **Vagrant** est installé à l'intérieur de Debian afin de créer et gérer les machines virtuelles nécessaires au projet.

L'architecture générale est donc la suivante :

    Machine physique
          |
          v
      VirtualBox
          |
          v
      VM Debian
          |
          v
       Vagrant
          |
       +--+--+
       |     |
       v     v
    Server  Agent


## Objectifs de la Partie 1

La Partie 1 a pour objectif de :

- créer deux machines virtuelles avec Vagrant ;
- utiliser une distribution Linux stable ;
- configurer les ressources des machines ;
- définir les noms des machines ;
- configurer des adresses IP privées fixes ;
- permettre la communication entre les deux machines ;
- configurer l'accès SSH sans mot de passe ;
- installer K3s en mode Server sur la première machine ;
- installer K3s en mode Agent sur la deuxième machine ;
- connecter l'Agent au Server ;
- installer et utiliser `kubectl`.


## Environnement de virtualisation

Le projet est exécuté dans une machine virtuelle Debian.

L'environnement utilise donc une virtualisation imbriquée :

    Machine physique
          |
          v
      VirtualBox
          |
          v
      VM Debian
       "khmessah"
          |
          v
       Vagrant
          |
          v
      VirtualBox
       /       \
      /         \
     v           v
  khmessahS   khmessahSW


### VirtualBox

**VirtualBox** est l'hyperviseur utilisé pour créer et exécuter les machines
virtuelles.

Dans ce projet, VirtualBox est utilisé à deux niveaux :

1. pour exécuter la machine virtuelle Debian principale ;
2. comme provider de Vagrant pour créer les deux machines virtuelles du
   projet.

### Vagrant

**Vagrant** est utilisé pour automatiser la création et la gestion des
machines virtuelles.

La configuration des machines est définie dans le fichier :

    p1/Vagrantfile

Vagrant utilise VirtualBox comme provider afin de créer les machines
virtuelles définies dans le `Vagrantfile`.


## Virtualisation imbriquée

Comme Vagrant est exécuté à l'intérieur d'une machine virtuelle Debian,
VirtualBox doit lui-même pouvoir créer d'autres machines virtuelles.

Cela nécessite l'activation de la virtualisation imbriquée
(**Nested Virtualization**).

La configuration utilisée est :

    Nested VT-x/AMD-V: enabled
    Nested Paging: enabled

Cette configuration permet à VirtualBox exécuté dans la machine Debian
d'utiliser les fonctionnalités de virtualisation du processeur.


## Les deux machines virtuelles

La Partie 1 nécessite deux machines virtuelles.

### Machine Server

Nom :

    khmessahS

Adresse IP :

    192.168.56.110

Rôle :

    K3s Server / Controller

Ressources :

    CPU : 1
    RAM : 1024 MB


### Machine Agent

Nom :

    khmessahSW

Adresse IP :

    192.168.56.111

Rôle :

    K3s Agent / ServerWorker

Ressources :

    CPU : 1
    RAM : 1024 MB


L'architecture finale est :

                    K3s Cluster
                         |
              +----------+----------+
              |                     |
              v                     v
        khmessahS              khmessahSW
        K3s Server              K3s Agent
        192.168.56.110          192.168.56.111


## Vagrantfile

Le fichier `Vagrantfile` contient la configuration des deux machines.

Il permet de définir :

- la distribution utilisée ;
- le provider VirtualBox ;
- le nom des machines ;
- les hostnames ;
- les adresses IP ;
- la mémoire RAM ;
- le nombre de CPU ;
- la configuration réseau.


### Définition du Server

Le Server est défini avec :

    config.vm.define "khmessahS"

Son hostname est :

    khmessahS

Son adresse IP privée est :

    192.168.56.110


### Définition de l'Agent

L'Agent est défini avec :

    config.vm.define "khmessahSW"

Son hostname est :

    khmessahSW

Son adresse IP privée est :

    192.168.56.111


## Réseau privé

Un réseau privé est utilisé afin de permettre aux deux machines de
communiquer directement entre elles.

Le Server possède :

    192.168.56.110

L'Agent possède :

    192.168.56.111

La communication peut être vérifiée avec la commande `ping`.

Depuis le Server :

    ping 192.168.56.111

Depuis l'Agent :

    ping 192.168.56.110


## SSH

Les machines doivent pouvoir être accessibles en SSH sans avoir besoin
d'entrer un mot de passe manuellement.

Vagrant fournit une commande permettant de se connecter directement aux
machines :

    vagrant ssh khmessahS

et :

    vagrant ssh khmessahSW

La configuration SSH est nécessaire pour permettre la gestion et la
communication entre les machines.


## K3s

**K3s** est une distribution légère de Kubernetes.

Dans cette partie, K3s est installé sur les deux machines avec deux rôles
différents :

- le Server fonctionne comme contrôleur du cluster ;
- l'Agent rejoint le cluster et exécute les workloads.


## K3s Server

Le K3s Server est installé sur :

    khmessahS

avec l'adresse :

    192.168.56.110

Le Server est responsable de la gestion du cluster Kubernetes.

Il fournit le control plane qui permet notamment de gérer les nœuds et les
workloads du cluster.


## K3s Agent

Le K3s Agent est installé sur :

    khmessahSW

avec l'adresse :

    192.168.56.111

L'Agent rejoint le cluster géré par le K3s Server.

Pour rejoindre le cluster, l'Agent utilise l'adresse du Server ainsi que le
token d'authentification fourni lors de l'installation du K3s Server.


## Connexion entre Server et Agent

Le fonctionnement attendu est :

                  K3s Server
                 192.168.56.110
                       |
                       | IP + Token
                       |
                       v
                  K3s Agent
                 192.168.56.111

Une fois l'Agent correctement configuré, les deux machines appartiennent au
même cluster K3s.


## kubectl

`kubectl` est l'outil en ligne de commande utilisé pour communiquer avec un
cluster Kubernetes.

Il permet notamment de vérifier l'état des nœuds du cluster.

Une commande importante est :

    kubectl get nodes

Elle permet de vérifier que les nœuds du cluster sont correctement
enregistrés.

D'autres commandes utiles sont :

    kubectl get pods -A

et :

    kubectl get nodes -o wide


## Commandes Vagrant utiles

### Vérifier la version de Vagrant

    vagrant --version


### Vérifier le Vagrantfile

    vagrant validate


### Démarrer le Server

    vagrant up khmessahS


### Démarrer l'Agent

    vagrant up khmessahSW


### Démarrer les deux machines

    vagrant up


### Vérifier l'état des machines

    vagrant status


### Se connecter au Server

    vagrant ssh khmessahS


### Se connecter à l'Agent

    vagrant ssh khmessahSW


### Arrêter les machines

    vagrant halt


### Supprimer les machines

    vagrant destroy


## Vérification du réseau

Après le démarrage des machines, la configuration réseau peut être vérifiée
avec :

    ip a

Cette commande permet d'afficher les interfaces réseau et leurs adresses IP.

La connectivité entre les deux machines peut ensuite être testée avec :

    ping 192.168.56.110

et :

    ping 192.168.56.111


## Vérification du cluster K3s

Une fois K3s installé sur les deux machines et l'Agent connecté au Server,
le cluster peut être vérifié avec :

    kubectl get nodes

Le résultat doit permettre d'identifier les nœuds du cluster K3s.


## Structure du projet

La structure de la Partie 1 est :

    p1/
    ├── Vagrantfile
    ├── README.md
    ├── scripts/
    └── confs/


### Vagrantfile

Contient la configuration des machines virtuelles.

### scripts/

Contient les scripts utilisés pour automatiser l'installation et la
configuration de l'environnement.

### confs/

Contient les fichiers de configuration nécessaires au projet.


## État d'avancement

### Environnement

- [x] Installation de Vagrant
- [x] Installation de VirtualBox
- [x] Création de la machine Debian principale
- [x] Activation de la virtualisation imbriquée
- [x] Configuration de VirtualBox comme provider Vagrant

### Machines virtuelles

- [x] Création de `khmessahS`
- [x] Création de `khmessahSW`
- [x] Configuration de l'adresse `192.168.56.110`
- [x] Configuration de l'adresse `192.168.56.111`
- [x] Configuration de 1 CPU
- [x] Configuration de 1024 MB de RAM

### K3s

- [ ] Installation du K3s Server
- [ ] Récupération du token
- [ ] Installation du K3s Agent
- [ ] Connexion de l'Agent au Server
- [ ] Vérification du cluster

### kubectl

- [ ] Installation de kubectl
- [ ] Vérification des nœuds avec `kubectl get nodes`

## Résultat attendu

À la fin de la Partie 1, nous devons obtenir un cluster K3s composé de deux
machines :

    +-----------------------------------+
    |           K3s Cluster             |
    |                                   |
    |  +-------------+ +-------------+  |
    |  | khmessahS   | | khmessahSW  |  |
    |  | Server      | | Agent       |  |
    |  | .110        | | .111        |  |
    |  +-------------+ +-------------+  |
    +-----------------------------------+

Le Server contrôle le cluster et l'Agent est connecté au Server pour
participer à l'exécution des workloads Kubernetes.

## Conclusion

Cette première partie permet de mettre en place l'infrastructure de base du
projet Inception of Things. Vagrant automatise la création des machines,
VirtualBox fournit l'environnement de virtualisation et K3s permet de créer
le cluster Kubernetes léger composé d'un Server et d'un Agent.

Une fois le réseau, SSH, K3s et kubectl correctement configurés et vérifiés,
la Partie 1 sera complète.