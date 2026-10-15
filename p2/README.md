# Inception of Things — Partie 2

## Description

La Partie 2 consiste à déployer trois applications web sur une seule machine virtuelle à l'aide de Kubernetes et de K3s.

La machine virtuelle utilise K3s en mode **Server** et les applications sont déployées avec des **Deployments**, des **Services** et un **Ingress**.

L'Ingress permet de diriger les requêtes HTTP vers la bonne application en fonction du champ `Host`.

---

## Objectifs

Cette partie demande :

- Une seule machine virtuelle.
- Une distribution Linux récente et stable.
- K3s installé en mode Server.
- Trois applications web.
- `app1.com` doit accéder à l'application 1.
- `app2.com` doit accéder à l'application 2.
- Tout autre Host doit accéder à l'application 3.
- L'application 2 doit avoir 3 replicas.
- La machine utilise l'adresse IP `192.168.56.110`.

---

## Structure du projet

```text
p2/
├── Vagrantfile
├── README.md
├── confs/
│   ├── apps/
│   │   ├── app1.yaml
│   │   ├── app1.service.yaml
│   │   ├── app2.yaml
│   │   ├── app2.service.yaml
│   │   ├── app3.yaml
│   │   └── app3.service.yaml
│   └── ingress.yaml
└── scripts/
    └── server.sh


1. Machine virtuelle
Une seule machine virtuelle est utilisée pour cette partie.
La machine est créée avec Vagrant et VirtualBox.
Configuration
- Nom de la machine : khmessahS
- Hostname : khmessahS
- Adresse IP : 192.168.56.110
- CPU : 1
- RAM : 2049 MB
- Système : Debian 13
- K3s : mode Server
La configuration de la machine virtuelle se trouve dans :
Vagrantfile

2. Installation et configuration
L'installation et la configuration de K3s sont entièrement automatisées avec :
scripts/server.sh

Le script de provisioning effectue automatiquement :
1. La mise à jour des paquets.
2. L'installation des dépendances nécessaires.
3. L'installation de K3s en mode Server.
4. La configuration de l'accès à Kubernetes.
5. L'attente jusqu'à ce que le nœud K3s soit prêt.
6. La configuration de l'alias k pour kubectl.
7. Le déploiement des trois applications.
8. Le déploiement de l'Ingress.
Aucune configuration Kubernetes manuelle n'est nécessaire après le lancement de la machine.
3. Applications
Trois applications web sont déployées dans Kubernetes.
Les trois applications utilisent l'image :
paulbouwer/hello-kubernetes:1.10

Chaque application utilise un Deployment et un Service Kubernetes.
Application 1
L'application 1 possède :
1 replica

Elle affiche :
bonjour vous etes dans application 1

Son Service est :
app1-service

Application 2
L'application 2 possède :
3 replicas

Elle affiche :
bonjour vous etes dans application 2

Son Service est :
app2-service

Les trois replicas permettent d'avoir trois Pods exécutant la même application.
Application 3
L'application 3 possède :
1 replica

Elle affiche :
bonjour vous etes dans application 3

Son Service est :
app3-service

L'application 3 est également utilisée comme application par défaut pour les Hosts qui ne correspondent pas à app1.com ou app2.com.
4. Services Kubernetes
Chaque application possède son propre Service :
app1-service
app2-service
app3-service

Les trois Services sont de type :
ClusterIP

Ils exposent le port :
80

et redirigent les requêtes vers le port 8080 des conteneurs.
Les Services permettent à l'Ingress de communiquer avec les Pods des applications.
5. Ingress
L'Ingress est utilisé pour router les requêtes HTTP vers les différentes applications en fonction du Host.
Le routage est le suivant :
app1.com   → Application 1
app2.com   → Application 2
autre Host → Application 3

L'Ingress possède une règle sans host pour l'application 3.
Cette règle permet de gérer tous les Hosts qui ne correspondent pas à app1.com ou app2.com.
Par exemple :
app1.com  → Application 1
app2.com  → Application 2
app3.com  → Application 3
test.com  → Application 3
test1.com → Application 3

6. Vérification de Kubernetes
Après le démarrage de la machine :
vagrant up

on peut accéder à la machine avec :
vagrant ssh khmessahS

Pour vérifier le nœud Kubernetes :
k get nodes

Résultat attendu :
khmessahs   Ready   control-plane

7. Vérification des Pods
Pour vérifier les Pods :
k get pods

Les résultats attendus sont :
App1 → 1 Pod
App2 → 3 Pods
App3 → 1 Pod

Les Pods doivent être dans l'état :
Running

8. Vérification des Deployments
Pour vérifier les Deployments :
k get deployment

Résultat attendu :
app1   1/1
app2   3/3
app3   1/1

L'application 2 doit donc avoir exactement trois replicas disponibles.
9. Vérification des Services
Pour vérifier les Services :
k get service

Les Services suivants doivent être présents :
app1-service
app2-service
app3-service

10. Vérification de l'Ingress
Pour vérifier l'Ingress :
k get ingress

L'Ingress doit être accessible via :
192.168.56.110

Pour obtenir plus de détails :
k describe ingress app-ingress

La règle importante pour l'application 3 apparaît comme une règle générale :
*  /  app3-service:80

Cela signifie que les Hosts qui ne correspondent pas à app1.com ou app2.com sont envoyés vers l'application 3.
11. Test du routage
Le routage peut être testé avec curl en utilisant directement l'adresse IP de la machine virtuelle.
Application 1
curl -H "Host: app1.com" http://192.168.56.110

Résultat attendu :
bonjour vous etes dans application 1

Application 2
curl -H "Host: app2.com" http://192.168.56.110

Résultat attendu :
bonjour vous etes dans application 2

Application 3
Avec un Host différent :
curl -H "Host: test.com" http://192.168.56.110

Résultat attendu :
bonjour vous etes dans application 3

Un autre Host peut également être utilisé :
curl -H "Host: test1.com" http://192.168.56.110

Résultat attendu :
bonjour vous etes dans application 3

Ces tests permettent de vérifier que l'Ingress respecte les règles de routage demandées.
12. Accès depuis le navigateur
Pour accéder aux applications depuis le navigateur avec leurs noms de domaine, les domaines peuvent être associés à l'adresse IP de la VM dans le fichier /etc/hosts de la machine hôte.
Exemple :
192.168.56.110 app1.com
192.168.56.110 app2.com
192.168.56.110 app3.com

On peut ensuite accéder aux applications avec :
http://app1.com
http://app2.com
http://app3.com

Pour tester un autre Host dans le navigateur, par exemple test.com, il faut également l'ajouter dans /etc/hosts :
192.168.56.110 test.com

Le fichier /etc/hosts sert uniquement à résoudre le nom de domaine vers l'adresse IP.
Le routage vers les applications est réalisé par l'Ingress Kubernetes.
13. Automatisation
L'ensemble de la configuration est automatisé.
Après avoir lancé :
vagrant up

la machine virtuelle est créée et le script de provisioning installe et configure automatiquement :
- K3s
- kubectl
- les Deployments
- les Services
- l'Ingress
Les fichiers de configuration Kubernetes sont présents dans :
confs/

et le script de provisioning est présent dans :
scripts/

14. Vérification finale
La configuration finale a été vérifiée avec :
k get nodes
k get pods
k get service
k get deployment
k get ingress

État final :
K3s Node       → Ready
Application 1  → 1/1 Running
Application 2  → 3/3 Running
Application 3  → 1/1 Running

Les trois Services sont disponibles :
app1-service
app2-service
app3-service

L'Ingress est disponible sur :
192.168.56.110

Le routage a été vérifié :
app1.com  → Application 1
app2.com  → Application 2
test.com  → Application 3
test1.com → Application 3

Conclusion
La Partie 2 permet de mettre en place une architecture Kubernetes simple avec une seule machine virtuelle K3s.
Les trois applications sont déployées avec Kubernetes et accessibles grâce à un Ingress.
Le routage final est :
                    ┌── app1.com ──→ Application 1
                    │
Client ──→ Ingress ─┼── app2.com ──→ Application 2
                    │                  └── 3 replicas
                    │
                    └── autre Host ──→ Application 3

La configuration est entièrement automatisée avec Vagrant et le script de provisioning.
```