# Inception

Infrastructure web multi-conteneurs déployée avec Docker Compose : un WordPress servi par NGINX en HTTPS, adossé à une base MariaDB et à un cache Redis, chaque service isolé dans son propre conteneur construit à partir d'une image Debian de base.

Projet réalisé dans le cadre du cursus **École 42 Paris**.

---

## Objectif

Le sujet impose des contraintes qui interdisent les raccourcis habituels :

- **Aucune image applicative préconstruite** — pas de `FROM wordpress`, pas de `FROM mariadb`. Chaque conteneur part d'une Debian nue, les paquets sont installés et configurés à la main.
- **Un processus principal par conteneur**, lancé au premier plan — pas de démon détaché, pas de `tail -f` artificiel pour maintenir le conteneur en vie.
- **Aucun secret en dur** dans les Dockerfiles ni dans le `docker-compose.yml` : tout passe par des variables d'environnement.
- **Persistance des données** au-delà du cycle de vie des conteneurs.
- **TLS obligatoire** — le site n'est accessible qu'en HTTPS.

---

## Architecture

```
                        :80 → redirection 301
                        :443 (TLS)
                            │
                    ┌───────▼────────┐
                    │     NGINX      │   Terminaison TLS
                    │   (Debian)     │   Unique point d'entrée
                    └───────┬────────┘
                            │ FastCGI :9000
                    ┌───────▼────────┐
                    │   WORDPRESS    │   PHP-FPM 7.4
                    │   (Debian)     │   Installé via WP-CLI
                    └───┬────────┬───┘
                        │        │
              MySQL :3306│        │:6379
                ┌───────▼──┐  ┌──▼───────┐
                │ MARIADB  │  │  REDIS   │
                │ (Debian) │  │ (Debian) │
                └──────────┘  └──────────┘

        Réseau bridge « inception » — isolé de l'hôte
```

**Seul NGINX expose des ports vers l'extérieur.** MariaDB et Redis ne sont joignables que depuis le réseau interne : aucun port ne leur est publié, ce qui les rend inaccessibles depuis l'hôte comme depuis le réseau local. Les conteneurs se résolvent entre eux par leur nom de service, assuré par le DNS interne de Docker.

---

## Les services

### NGINX — point d'entrée et terminaison TLS

Construit depuis `debian:bullseye`, avec NGINX et OpenSSL.

Au démarrage, le script d'initialisation génère un certificat auto-signé RSA 2048 bits valable un an, puis restreint les permissions de la clé privée à son seul propriétaire avant de lancer NGINX au premier plan.

La configuration applique :

- Une redirection permanente (301) de tout le trafic HTTP vers HTTPS
- **TLSv1.2 exclusivement** — les versions antérieures sont désactivées
- Le passage des requêtes `.php` au conteneur WordPress via FastCGI, sur le port 9000
- Les journaux redirigés vers `stdout` et `stderr`, afin qu'ils soient collectés par Docker plutôt qu'écrits dans un fichier perdu à la destruction du conteneur

### WordPress — application

Debian + PHP-FPM 7.4, avec les extensions `php-mysqli` et `php-redis`.

Le script d'initialisation orchestre une installation complète et automatisée :

1. **Idempotence** — si `wp-config.php` existe déjà, l'installation est court-circuitée et PHP-FPM démarre directement. Le conteneur peut donc être redémarré sans réinitialiser le site.
2. **Attente active de MariaDB** — une boucle interroge la base via `mysqladmin ping` jusqu'à ce qu'elle réponde. `depends_on` garantit l'ordre de démarrage, pas la disponibilité réelle du service : cette boucle comble l'écart.
3. **Installation via WP-CLI** — téléchargement du cœur, génération de la configuration, création du site et du compte administrateur, puis d'un utilisateur secondaire avec le rôle *author*.
4. **Activation du cache Redis** — installation du plugin et branchement sur le conteneur Redis.
5. **Lancement de PHP-FPM au premier plan** (`-F`), conformément à la contrainte du sujet.

### MariaDB — persistance

Debian + `mariadb-server`.

Le script génère au démarrage un fichier `init.sql` à partir des variables d'environnement :

```sql
CREATE DATABASE IF NOT EXISTS <database>;
CREATE USER IF NOT EXISTS '<user>'@'%' IDENTIFIED BY '<password>';
GRANT ALL PRIVILEGES ON <database>.* TO '<user>'@'%';
FLUSH PRIVILEGES;
```

Les clauses `IF NOT EXISTS` rendent l'opération rejouable sans erreur sur un volume déjà initialisé. Les privilèges sont limités à la base du projet, et non accordés globalement.

La configuration serveur autorise l'écoute sur l'interface réseau du conteneur, sans quoi WordPress ne pourrait pas s'y connecter.

### Redis — cache objet

Debian + `redis-server`, lancé directement comme processus principal.

Il stocke en mémoire les résultats des requêtes récurrentes de WordPress, ce qui réduit la charge sur MariaDB.

---

## Réseau et persistance

Les conteneurs communiquent sur un réseau `bridge` dédié, déclaré explicitement — le sujet interdit `network: host` et `--link`.

Les volumes sont des **bind mounts** : la base de données et les fichiers WordPress sont stockés dans un répertoire de l'hôte, ce qui garantit leur survie à un `docker-compose down` comme à une reconstruction complète des images.

---

## Gestion des secrets

Identifiants de base de données et comptes WordPress sont centralisés dans un fichier `.env`, injecté dans les conteneurs via `env_file`. Ce fichier est **exclu du dépôt** par `.gitignore`.

Le modèle [`srcs/.env.example`](srcs/.env.example) documente les variables attendues sans en révéler les valeurs.

---

## Installation

Prérequis : Docker, Docker Compose, `make`.

```bash
# 1. Créer le fichier d'environnement à partir du modèle
cp srcs/.env.example srcs/.env
# puis renseigner les valeurs

# 2. Construire et démarrer
make

# 3. Arrêter
make down

# 4. Reconstruire entièrement
make re
```

Le domaine doit être résolu vers l'hôte. En local, ajouter dans `/etc/hosts` :

```
127.0.0.1    <domaine>
```

Le certificat étant auto-signé, le navigateur affichera un avertissement au premier accès — comportement attendu.

---

## Ce que le projet m'a apporté

- **Construire une image plutôt que la consommer** — repartir d'une Debian nue oblige à comprendre ce qu'une image officielle fait à votre place : quels paquets, quelle configuration, quel processus lance réellement le service.
- **Cycle de vie des conteneurs** — saisir la différence entre l'ordre de démarrage et la disponibilité effective d'un service, et pourquoi une attente active reste nécessaire malgré `depends_on`.
- **Isolation réseau** — n'exposer que ce qui doit l'être, et s'appuyer sur la résolution DNS interne plutôt que sur des adresses IP.
- **Persistance** — distinguer ce qui appartient au conteneur, éphémère par nature, de ce qui doit lui survivre.
- **Gestion des secrets** — externaliser les identifiants et ne jamais les versionner.
- **Automatisation d'un déploiement** — écrire des scripts d'initialisation rejouables, qui ne cassent pas au second lancement.
