# Guide de bout en bout — Starter WordPress Coolify

Ce guide part de zéro et va jusqu'à un site WordPress en ligne, avec un accès SSH/SFTP/WP-CLI
passant par un tunnel Cloudflare (aucun port SSH ouvert sur le serveur).

> Les libellés de menus Cloudflare cités ici viennent de la documentation officielle Cloudflare
> (novembre 2026). Les interfaces évoluent : en cas d'écart, référez-vous aux liens en fin de guide.
> Pour Coolify, seuls les noms de champs confirmés dans sa documentation sont cités.

---

## Sommaire

1. Architecture
2. Prérequis
3. Étape 1 — Générer la clé SSH (poste client)
4. Étape 2 — Créer le tunnel Cloudflare et récupérer le jeton
5. Étape 3 — Pousser le starter dans un dépôt Git
6. Étape 4 — Créer la ressource dans Coolify
7. Étape 5 — Renseigner les variables d'environnement
8. Étape 6 — Déployer et attribuer le domaine du site
9. Étape 7 — Ajouter la route SSH dans le tunnel Cloudflare
10. Étape 8 — Configurer le poste client et se connecter
11. Étape 9 — Vérifier l'UID/GID des fichiers
12. Étape 10 — Installer WordPress et activer Redis via LiteSpeed Cache
13. Référence complète des variables
14. Dépannage
15. Plusieurs sites sur le même serveur
16. Liens de référence

---

## 1. Architecture

```
Visiteurs ──HTTPS──> Proxy Coolify ──HTTP:80──> wordpress (OpenLiteSpeed + lsphp85 + LSCache)
                                                     │
                                         ┌───────────┴───────────┐
                                         │                       │
                                       db (MariaDB)        redis (object cache)
                                         │
Toi ──SSH──> Cloudflare ──tunnel sortant──> cloudflared ──> ssh (sshd + WP-CLI)
                                                              │
                                                  volume wp_data partagé avec wordpress
```

| Service       | Image                                       | Rôle                                                  |
|---------------|---------------------------------------------|-------------------------------------------------------|
| `db`          | `mariadb:10.11`                             | Base de données                                       |
| `redis`       | `redis:7-alpine`                            | Cache objet (sans persistance disque)                 |
| `wordpress`   | construite depuis `wordpress/Dockerfile` (base `litespeedtech/openlitespeed:1.8.5-lsphp85`) | Serveur web + PHP 8.5 + cache de page LSCache ; réglages PHP par variables |
| `ssh`         | construite depuis `ssh/Dockerfile`          | SSH, SFTP, WP-CLI, client MariaDB, `redis-cli`        |
| `cloudflared` | `cloudflare/cloudflared:latest`             | Tunnel sortant vers Cloudflare pour l'accès SSH       |

Au premier démarrage, le conteneur `ssh` télécharge WordPress et génère `wp-config.php`.

---

## 2. Prérequis

- Un serveur géré par Coolify (v4), avec son proxy actif.
- Un dépôt Git accessible par Coolify (GitHub, GitLab, Gitea…). Le service `ssh` utilise
  `build:`, ce qui impose un déploiement depuis Git : coller le compose directement ne suffit pas.
- Un compte Cloudflare avec le domaine ajouté à Cloudflare (requis pour publier une route de tunnel).
- Sur ton poste : un client OpenSSH (inclus sous macOS, Linux et Windows 10/11) et `cloudflared`.

---

## 3. Étape 1 — Générer la clé SSH (poste client)

Si tu as déjà une clé `~/.ssh/id_ed25519.pub`, passe à l'étape suivante.

**macOS / Linux / Windows (PowerShell)** :

```bash
ssh-keygen -t ed25519 -C "henoc@poste"
```

Accepte l'emplacement par défaut et choisis une phrase de passe.

Affiche ensuite la clé publique :

```bash
# macOS / Linux
cat ~/.ssh/id_ed25519.pub

# Windows PowerShell
Get-Content $env:USERPROFILE\.ssh\id_ed25519.pub
```

Exemple de résultat (c'est **toute cette ligne** qui va dans `SSH_PUBLIC_KEY`) :

```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExempleExempleExempleExempleExemple henoc@poste
```

⚠️ Ne copie jamais le fichier sans `.pub` : c'est ta clé privée, elle ne quitte pas ton poste.

**Plusieurs clés** (plusieurs postes ou collaborateurs) : `SSH_PUBLIC_KEY` accepte plusieurs lignes,
une clé par ligne.

---

## 4. Étape 2 — Créer le tunnel Cloudflare et récupérer le jeton

1. Connecte-toi au tableau de bord Cloudflare et va dans **Networking > Tunnels**.
2. Sélectionne **Create a tunnel**.
3. Donne-lui un nom explicite, par exemple `coolify-client1-ssh`, puis **Create Tunnel**.
4. Cloudflare affiche une commande d'installation à exécuter sur le serveur.
   **Ne l'exécute pas** : dans ce starter, c'est le conteneur `cloudflared` qui joue ce rôle.
   Copie seulement le **jeton** contenu dans cette commande : c'est la longue chaîne qui commence
   généralement par `eyJ`, placée à la fin de la commande.

   Exemple de commande affichée (jeton raccourci) :
   ```
   sudo cloudflared service install eyJhIjoiMTIzNDU2Nzg5MGFiY2RlZiIsInQiOiJhYmNkLWVmZ2gi...
   ```
   Le jeton est uniquement la partie `eyJhIjoi...` → elle ira dans `CLOUDFLARE_TUNNEL_TOKEN`.

5. Garde cette page ouverte. Le tunnel apparaîtra « connecté » une fois le conteneur `cloudflared`
   déployé (étape 6). Tu reviendras ensuite ajouter la route SSH (étape 7).

> Le jeton donne le droit de faire tourner ce tunnel : traite-le comme un mot de passe.
> Il ne doit pas être commité dans Git, seulement saisi dans Coolify.

**Un tunnel par site** : avec ce starter, chaque site a son propre conteneur `cloudflared`,
donc son propre tunnel et son propre jeton. Voir la section 15 pour un parc de nombreux sites.

---

## 5. Étape 3 — Pousser le starter dans un dépôt Git

```bash
cd wordpress-coolify-starter
git init
git add .
git commit -m "chore: add WordPress Coolify starter"
git branch -M main
git remote add origin git@github.com:ton-compte/wp-client1.git
git push -u origin main
```

Vérifie que `ssh/entrypoint.sh` est bien exécutable dans le dépôt :

```bash
git ls-files -s ssh/entrypoint.sh   # doit commencer par 100755
# sinon :
git update-index --chmod=+x ssh/entrypoint.sh && git commit -m "fix: make ssh entrypoint executable" && git push
```

**Règle des commits** : les messages de commit sont **toujours en anglais**, à l'impératif, au format
Conventional Commits (`type: description`). Exemples :

| Type       | Exemple                                         |
|------------|-------------------------------------------------|
| `feat`     | `feat: add Cloudflare tunnel service`           |
| `fix`      | `fix: align deploy user UID with lsphp`         |
| `chore`    | `chore: bump OpenLiteSpeed to 1.8.5-lsphp85`    |
| `docs`     | `docs: document tunnel token retrieval`         |
| `refactor` | `refactor: split ssh bootstrap into functions`  |

Ne commite **jamais** un fichier `.env` rempli : seul `.env.example` (vide) fait partie du dépôt.

---

## 6. Étape 4 — Créer la ressource dans Coolify

Crée une nouvelle ressource de type **Docker Compose** à partir de ton dépôt Git. Coolify demande
notamment :

| Champ                       | Valeur                                      |
|-----------------------------|---------------------------------------------|
| **Branch**                  | `main`                                      |
| **Base Directory**          | `/` (ou le sous-dossier si le starter n'est pas à la racine) |
| **Docker Compose Location** | `/docker-compose.yml`                       |

Coolify lit le compose et affiche les services (`db`, `redis`, `wordpress`, `ssh`, `cloudflared`).

---

## 7. Étape 5 — Renseigner les variables d'environnement

Les variables se gèrent dans **Configuration > Environment Variables** de la ressource.

### À renseigner toi-même

| Variable                  | Obligatoire | Exemple                                         | Comment l'obtenir                       |
|---------------------------|-------------|-------------------------------------------------|-----------------------------------------|
| `SSH_PUBLIC_KEY`          | Oui*        | `ssh-ed25519 AAAAC3Nza... henoc@poste`          | Étape 1                                 |
| `CLOUDFLARE_TUNNEL_TOKEN` | Oui         | `eyJhIjoiMTIzNDU2...`                           | Étape 2                                 |
| `SSH_PASSWORD`            | Non         | *(vide)*                                        | Laisser vide (recommandé), voir § 13    |
| `WEB_UID`                 | Non         | `65534`                                         | Défaut, à vérifier à l'étape 9          |
| `WEB_GID`                 | Non         | `65534`                                         | Défaut, à vérifier à l'étape 9          |
| `DB_NAME`                 | Non         | `wordpress`                                     | Nom libre                               |
| `WP_LOCALE`               | Non         | `fr_FR`                                         | Code de langue WordPress                |

\* `SSH_PUBLIC_KEY` ou `SSH_PASSWORD` doit être défini, sinon le conteneur `ssh` refuse de démarrer.

### Générées automatiquement par Coolify (ne rien saisir)

| Variable                          | Contenu                                           | Utilisée par              |
|-----------------------------------|---------------------------------------------------|---------------------------|
| `SERVICE_USER_MARIADB`            | Nom d'utilisateur MariaDB aléatoire               | `db`, `ssh` (wp-config)   |
| `SERVICE_PASSWORD_64_MARIADB`     | Mot de passe MariaDB, 64 caractères               | `db`, `ssh` (wp-config)   |
| `SERVICE_PASSWORD_64_MARIADBROOT` | Mot de passe root MariaDB, 64 caractères          | `db`                      |
| `SERVICE_PASSWORD_REDIS`          | Mot de passe Redis                                | `redis`, réglage LSCache  |
| `SERVICE_FQDN_WORDPRESS_80`       | Domaine du site, routé vers le port 80 du conteneur `wordpress` | proxy Coolify |

Ces valeurs sont conservées entre les déploiements et visibles dans la même liste de variables.
C'est là que tu iras lire `SERVICE_PASSWORD_REDIS` à l'étape 10.

⚠️ Ne modifie pas `SERVICE_PASSWORD_64_MARIADB` après le premier déploiement : MariaDB a déjà été
initialisée avec l'ancienne valeur, et `wp-config.php` aussi. Un changement casserait la connexion.

---

## 8. Étape 6 — Déployer et attribuer le domaine du site

1. Attribue au service `wordpress` le domaine du site, par exemple `https://client1.com`.
   (Le domaine doit pointer vers l'IP du serveur Coolify via un enregistrement DNS A/AAAA.)
2. Lance le déploiement.
3. Dans les journaux du service `ssh`, tu dois voir :
   ```
   Téléchargement de WordPress (fr_FR)...
   Création de wp-config.php...
   SSH prêt (utilisateur: deploy, mot de passe: no)
   ```
4. Dans Cloudflare (page du tunnel), le tunnel doit maintenant apparaître connecté.

**Si le domaine du site est lui-même chez Cloudflare** : l'enregistrement DNS peut être proxifié
(nuage orange) ou non. S'il est proxifié, règle le mode SSL/TLS de Cloudflare sur « Full (strict) »
pour éviter une boucle de redirection.

---

## 9. Étape 7 — Ajouter la route SSH dans le tunnel Cloudflare

1. Dans **Networking > Tunnels**, sélectionne ton tunnel.
2. Onglet **Routes** → **Add route** → **Published application**.
3. Sous-domaine : `ssh-client1` ; **Domain** : ton domaine (par ex. `ton-agence.com`).
4. **Service** : type **SSH**, adresse **`ssh:22`**.
   `ssh` est le nom du service dans le compose : `cloudflared` le joint par le réseau interne de la stack.
   (La documentation Cloudflare montre `localhost:22` parce qu'elle suppose `cloudflared` installé
   sur la même machine que sshd ; ici ce sont deux conteneurs distincts.)
5. **Add route**.

Cloudflare crée automatiquement l'enregistrement DNS `ssh-client1.ton-agence.com`.

### Recommandé : protéger avec Cloudflare Access

Cloudflare recommande d'ajouter une application Access de type self-hosted sur ce nom d'hôte,
pour exiger une authentification (e-mail, Google, etc.) **avant même** d'atteindre sshd.
Avec Access, `cloudflared` ouvre ton navigateur à la première connexion pour te faire valider.
Voir le lien « Cloudflare Access » en fin de guide.

---

## 10. Étape 8 — Configurer le poste client et se connecter

### Installer cloudflared

```bash
# macOS
brew install cloudflared

# Windows
winget install --id Cloudflare.cloudflared

# Linux : paquets .deb/.rpm sur la page des versions GitHub de cloudflared (lien en fin de guide)
```

### Configurer SSH

Ajoute dans `~/.ssh/config` (Windows : `C:\Users\<toi>\.ssh\config`) :

```
Host ssh-client1.ton-agence.com
  User deploy
  IdentityFile ~/.ssh/id_ed25519
  ProxyCommand cloudflared access ssh --hostname %h
```

Si `cloudflared` n'est pas dans le PATH, indique son chemin complet dans `ProxyCommand`
(macOS Homebrew : `brew --prefix cloudflared` pour le trouver).

### Utilisation

```bash
# Shell (arrive directement dans le dossier WordPress)
ssh ssh-client1.ton-agence.com

# SFTP
sftp ssh-client1.ton-agence.com

# Copier un fichier
scp ./sauvegarde.sql ssh-client1.ton-agence.com:/tmp/

# Synchroniser un thème
rsync -avz ./mon-theme/ ssh-client1.ton-agence.com:/var/www/vhosts/localhost/html/wp-content/themes/mon-theme/

# Tunnel vers MariaDB (puis TablePlus/DBeaver sur 127.0.0.1:3307)
ssh -N -L 3307:db:3306 ssh-client1.ton-agence.com
```

Pour le tunnel MariaDB, les identifiants sont `SERVICE_USER_MARIADB` / `SERVICE_PASSWORD_64_MARIADB`.

**Clients SFTP graphiques** : FileZilla ne sait pas utiliser `ProxyCommand`. Utilise un outil
qui s'appuie sur ta config OpenSSH (VS Code Remote-SSH, ou `sftp`/`rsync` en ligne de commande).

---

## 11. Étape 9 — Vérifier l'UID/GID des fichiers

Le compte `deploy` doit avoir le même UID/GID que le process PHP d'OpenLiteSpeed. Sinon, les fichiers
que tu crées en SSH ne seront pas modifiables par WordPress (mises à jour, uploads, cache), ou l'inverse.

Ouvre un terminal **dans le conteneur `wordpress`** (terminal Coolify, ou `docker exec -it <conteneur> bash`
sur le serveur) :

```bash
# Utilisateur/groupe configurés pour OpenLiteSpeed
grep -E '^\s*(user|group)\s' /usr/local/lsws/conf/httpd_config.conf

# UID/GID correspondants (remplacer nobody/nogroup par ce qui s'affiche)
id nobody
getent group nogroup
```

Exemple de sortie :

```
user                      nobody
group                     nogroup
uid=65534(nobody) gid=65534(nogroup) groups=65534(nogroup)
nogroup:x:65534:
```

→ ici `WEB_UID=65534` et `WEB_GID=65534` (les valeurs par défaut sont bonnes).

**Si les valeurs diffèrent** :

1. Mets à jour `WEB_UID` / `WEB_GID` dans Coolify et redéploie.
2. Corrige la propriété des fichiers déjà créés, depuis un terminal root dans le conteneur `ssh` :
   ```bash
   chown -R <WEB_UID>:<WEB_GID> /var/www/vhosts/localhost/html
   ```

---

## 12. Étape 10 — Installer WordPress et activer Redis via LiteSpeed Cache

Connecté en SSH :

```bash
wp core install \
  --url="https://client1.com" \
  --title="Client 1" \
  --admin_user="admin_client1" \
  --admin_email="contact@client1.com"
# WP-CLI génère et affiche un mot de passe admin : note-le.

wp plugin install litespeed-cache --activate
```

Récupère `SERVICE_PASSWORD_REDIS` dans les variables de la ressource Coolify, puis :

```bash
# Vérifier d'abord les noms exacts des options dans ta version du plugin
wp litespeed-option all | grep -i object

wp litespeed-option set object true
wp litespeed-option set object-kind 1        # 1 = Redis
wp litespeed-option set object-host redis
wp litespeed-option set object-port 6379
wp litespeed-option set object-pswd 'COLLE_ICI_SERVICE_PASSWORD_REDIS'
```

Vérifications :

```bash
# Redis répond
redis-cli -h redis -a 'COLLE_ICI_SERVICE_PASSWORD_REDIS' --no-auth-warning ping   # -> PONG

# Des clés apparaissent après quelques pages vues
redis-cli -h redis -a 'COLLE_ICI_SERVICE_PASSWORD_REDIS' --no-auth-warning dbsize

# Cache de page LSCache : l'en-tête x-litespeed-cache doit valoir "hit" au 2e chargement
curl -sI https://client1.com | grep -i x-litespeed-cache
```

Et dans le conteneur `wordpress`, vérifie que l'extension PHP Redis est chargée :

```bash
/usr/local/lsws/lsphp85/bin/php -m | grep -i redis
```

---

## 13. Référence complète des variables

### `SSH_PUBLIC_KEY`
- **Rôle** : clé(s) publique(s) autorisée(s) à se connecter en tant que `deploy`.
- **Format** : une clé par ligne, ligne complète (`type clé commentaire`).
- **Exemple** : `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExemple henoc@poste`
- **Obtention** : `ssh-keygen -t ed25519` puis `cat ~/.ssh/id_ed25519.pub` (étape 1).
- **Révoquer un accès** : retirer la ligne, redéployer. Le fichier `authorized_keys` est réécrit à chaque démarrage.

### `SSH_PASSWORD`
- **Rôle** : active l'authentification par mot de passe si non vide.
- **Recommandation** : laisser vide. Avec Cloudflare Access en façade le risque est réduit, mais une clé reste plus sûre.
- **Exemple** : *(vide)* ; si besoin ponctuel : une valeur générée par `openssl rand -base64 24`.

### `CLOUDFLARE_TUNNEL_TOKEN`
- **Rôle** : autorise le conteneur `cloudflared` à faire tourner le tunnel.
- **Exemple** : `eyJhIjoiMTIzNDU2Nzg5MGFiY2RlZiIsInQiOiJhYmNkLWVmZ2gi...` (très long).
- **Obtention** : étape 2, la chaîne `eyJ...` dans la commande d'installation affichée par Cloudflare.
- **Fuite ou rotation** : régénère le jeton du tunnel côté Cloudflare, mets à jour la variable, redéploie.

### `WEB_UID` / `WEB_GID`
- **Rôle** : UID/GID donnés à `deploy`, alignés sur le process PHP d'OpenLiteSpeed.
- **Défaut** : `65534` / `65534` (`nobody` / `nogroup`).
- **Obtention** : étape 9.

### `DB_NAME`
- **Rôle** : nom de la base créée au premier démarrage de MariaDB.
- **Défaut** : `wordpress`. À fixer avant le premier déploiement : le changer ensuite ne renomme pas la base.

### `WP_LOCALE`
- **Rôle** : langue de WordPress téléchargée au premier démarrage.
- **Exemples** : `fr_FR`, `en_US`. Sans effet une fois WordPress téléchargé.

### Variables `SERVICE_*`
Générées et persistées par Coolify (voir tableau de l'étape 5). Ne pas les saisir.
`SERVICE_FQDN_WORDPRESS_80` dépend du domaine attribué au service `wordpress`.

### Réglages PHP du site (service `wordpress`)

Écrits à chaque démarrage dans un bloc en fin du `php.ini` de lsphp
(`/usr/local/lsws/lsphp85/etc/php/8.5/litespeed/php.ini`). Modifier la variable dans Coolify, puis redéployer.

| Variable | Défaut | Directive PHP | Notes |
|----------|--------|---------------|-------|
| `PHP_MEMORY_LIMIT` | `512M` | `memory_limit` | Mémoire max par requête |
| `PHP_UPLOAD_MAX_FILESIZE` | `128M` | `upload_max_filesize` | Taille max d'un fichier envoyé |
| `PHP_POST_MAX_SIZE` | `128M` | `post_max_size` | Doit être ≥ `PHP_UPLOAD_MAX_FILESIZE` |
| `PHP_MAX_EXECUTION_TIME` | `300` | `max_execution_time` | Secondes |
| `PHP_MAX_INPUT_TIME` | `300` | `max_input_time` | Secondes |
| `PHP_MAX_INPUT_VARS` | `5000` | `max_input_vars` | Menus, WooCommerce, constructeurs de pages |
| `PHP_MAX_FILE_UPLOADS` | `50` | `max_file_uploads` | Fichiers par requête |
| `PHP_DATE_TIMEZONE` | `UTC` | `date.timezone` | Ex. `Africa/Abidjan` (aussi appliqué à WP-CLI) |
| `PHP_DISPLAY_ERRORS` | `Off` | `display_errors` | `On` seulement hors production |
| `PHP_ERROR_REPORTING` | `E_ALL & ~E_DEPRECATED` | `error_reporting` | |
| `PHP_REALPATH_CACHE_SIZE` | `4096K` | `realpath_cache_size` | |
| `PHP_SESSION_GC_MAXLIFETIME` | `1440` | `session.gc_maxlifetime` | Secondes |
| `PHP_OPCACHE_ENABLE` | `1` | `opcache.enable` | |
| `PHP_OPCACHE_MEMORY_CONSUMPTION` | `256` | `opcache.memory_consumption` | Mo |
| `PHP_OPCACHE_INTERNED_STRINGS_BUFFER` | `16` | `opcache.interned_strings_buffer` | Mo |
| `PHP_OPCACHE_MAX_ACCELERATED_FILES` | `20000` | `opcache.max_accelerated_files` | |
| `PHP_OPCACHE_VALIDATE_TIMESTAMPS` | `1` | `opcache.validate_timestamps` | `0` = plus rapide, mais redémarrer après chaque modification de code |
| `PHP_OPCACHE_REVALIDATE_FREQ` | `2` | `opcache.revalidate_freq` | Secondes |
| `PHP_EXTRA_INI` | *(vide)* | libre | Directives supplémentaires, une par ligne. Ex. `opcache.jit = tracing` |

Vérification, dans le conteneur `wordpress` :
```bash
tail -n 25 /usr/local/lsws/lsphp85/etc/php/8.5/litespeed/php.ini
```

### PHP de WP-CLI (service `ssh`)

| Variable | Défaut | Rôle |
|----------|--------|------|
| `WPCLI_MEMORY_LIMIT` | `512M` | `memory_limit` de WP-CLI. 128M ne suffit pas à extraire l'archive WordPress |
| `PHP_DATE_TIMEZONE` | `UTC` | Même variable que pour le site |

### Constantes WordPress (`wp-config.php`)

Appliquées par le conteneur `ssh` **à chaque démarrage** avec `wp config set`.
Une variable vide laisse la constante telle qu'elle est dans `wp-config.php`.
Pour supprimer une constante déjà écrite : `wp config delete NOM_DE_LA_CONSTANTE`.

| Variable | Défaut | Rôle |
|----------|--------|------|
| `WP_MEMORY_LIMIT` | `256M` | Mémoire côté site (≤ `PHP_MEMORY_LIMIT`) |
| `WP_MAX_MEMORY_LIMIT` | `512M` | Mémoire côté administration |
| `WP_DEBUG` | `false` | Mode débogage |
| `WP_DEBUG_LOG` | `false` | `true` = journal dans `wp-content/debug.log` |
| `WP_DEBUG_DISPLAY` | `false` | Affiche les erreurs à l'écran (jamais en production) |
| `WP_ENVIRONMENT_TYPE` | `production` | `production`, `staging`, `development` ou `local` |
| `DISALLOW_FILE_EDIT` | `true` | Désactive l'éditeur de thèmes/extensions dans l'admin |
| `DISALLOW_FILE_MODS` | *(vide)* | `true` = aucune installation ni mise à jour depuis l'admin (tout via WP-CLI) |
| `WP_POST_REVISIONS` | `10` | Nombre de révisions conservées (`false` = aucune) |
| `AUTOSAVE_INTERVAL` | `120` | Secondes entre deux sauvegardes automatiques |
| `EMPTY_TRASH_DAYS` | `30` | Jours avant vidage de la corbeille |
| `DISABLE_WP_CRON` | `false` | `true` si un vrai cron appelle `wp cron event run --due-now` |
| `WP_AUTO_UPDATE_CORE` | `minor` | `true`, `false` ou `minor` |
| `FORCE_SSL_ADMIN` | `true` | Force l'HTTPS sur l'administration |

Les valeurs `true`, `false` et les nombres entiers sont écrits tels quels ; les autres (`256M`, `production`, `minor`)
sont écrites entre guillemets.

### Redis

| Variable | Défaut | Rôle |
|----------|--------|------|
| `REDIS_MAXMEMORY` | `256mb` | Mémoire max de Redis avant éviction des clés les moins utilisées |

---

## 14. Dépannage

| Symptôme | Cause probable | Solution |
|----------|----------------|----------|
| Le conteneur `ssh` redémarre en boucle avec « ERREUR : définis SSH_PUBLIC_KEY » | Aucune clé ni mot de passe | Renseigner `SSH_PUBLIC_KEY` |
| Le conteneur `ssh` redémarre en boucle avec « Allowed memory size of 134217728 bytes exhausted » | Limite mémoire de WP-CLI trop basse | Augmenter `WPCLI_MEMORY_LIMIT` (512M par défaut) et redéployer |
| Un réglage PHP n'est pas pris en compte | Conteneur non recréé, ou valeur écrasée par `PHP_EXTRA_INI` | Redéployer ; vérifier le bloc `starter-env` en fin du `php.ini` de lsphp |
| `Fatal error ... wp-config.php` après changement d'une variable `WP_*` | Valeur invalide pour la constante | Corriger la variable, ou `wp config delete <CONSTANTE>`, puis redéployer |
| Boucle de redirection 301 vers la même URL, `server: LiteSpeed` | WordPress absent (conteneur `ssh` en échec) ou règle `.htaccess` testant `%{HTTPS}` | Corriger le conteneur `ssh` ; remplacer la condition par `%{HTTP:X-Forwarded-Proto} !https` |
| `exec /entrypoint.sh: permission denied` | Script non exécutable dans Git | Étape 3, `git update-index --chmod=+x` |
| Build en échec sur `FROM wordpress:cli-php8.5` | Tag absent de Docker Hub | Vérifier les tags `wordpress:cli-*`, ajuster `PHP_VERSION` |
| Erreur 404 ou boucle 301 servie par LiteSpeed | Volume `wp_data` monté hors du docRoot réellement servi | Dans `wordpress`, monter `wp_data` sur `/var/www/vhosts/localhost/html` (vhost `localhost` du template `docker`), pas sur `/usr/local/lsws/Example/html` |
| « Error establishing a database connection » | MariaDB pas prête ou mot de passe modifié après coup | Journaux de `db` ; ne pas changer les mots de passe générés |
| Boucle de redirection HTTPS | Proxy TLS non détecté, ou Cloudflare en mode « Flexible » | Vérifier le bloc `HTTP_X_FORWARDED_PROTO` dans `wp-config.php` ; Cloudflare en « Full (strict) » |
| Tunnel « inactif » dans Cloudflare | Jeton erroné ou `cloudflared` arrêté | Journaux du service `cloudflared` |
| `ssh` : « websocket: bad handshake » ou connexion fermée | Route mal configurée | Route de type **SSH**, adresse `ssh:22` |
| `Permission denied (publickey)` | Mauvaise clé ou mauvais utilisateur | `User deploy`, bonne `IdentityFile`, clé présente dans `SSH_PUBLIC_KEY` |
| WordPress ne peut pas installer de plugin / uploads en échec | UID/GID non alignés | Étape 9 |
| `x-litespeed-cache: miss` en permanence | Connecté à l'admin, ou cache désactivé | Tester en navigation privée ; vérifier les réglages LSCache |

Commandes utiles pour diagnostiquer, sur le serveur :

```bash
docker ps --format '{{.Names}}\t{{.Status}}' | grep -E 'wordpress|ssh|db|redis|cloudflared'
docker logs <conteneur> --tail 100
```

---

## 15. Plusieurs sites sur le même serveur

Chaque site = un dépôt (ou une branche) déployé comme une ressource Coolify séparée, avec :

- son propre domaine pour `wordpress` ;
- son propre tunnel Cloudflare et donc son propre `CLOUDFLARE_TUNNEL_TOKEN` ;
- son propre nom d'hôte SSH (`ssh-client1…`, `ssh-client2…`).

Aucun port n'est publié, donc pas de conflit. Chaque stack a son réseau : le `cloudflared` d'un site
ne joint que le conteneur `ssh` de ce site.

Convention de nommage conseillée :

| Élément              | Exemple                          |
|----------------------|----------------------------------|
| Tunnel Cloudflare    | `coolify-client1-ssh`            |
| Nom d'hôte SSH       | `ssh-client1.ton-agence.com`     |
| Entrée `~/.ssh/config` | `Host ssh-client1.ton-agence.com` |

Pour des dizaines de sites, un point d'entrée SSH unique (bastion ou routage par nom d'utilisateur)
évite de multiplier les tunnels ; ce n'est pas inclus dans ce starter.

---

## 16. Liens de référence

- Coolify — Docker Compose et variables générées : https://coolify.io/docs/services/configuration/docker-compose
- Coolify — Docker Compose depuis Git : https://coolify.io/docs/builds/packs/docker-compose
- Coolify — Variables d'environnement : https://coolify.io/docs/services/configuration/environment-variables
- Cloudflare — Créer un tunnel (tableau de bord) : https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/get-started/create-remote-tunnel/
- Cloudflare — SSH avec cloudflared côté client : https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/use-cases/ssh/ssh-cloudflared-authentication/
- cloudflared — versions et paquets (.deb, .rpm, Windows, macOS) : https://github.com/cloudflare/cloudflared/releases
- Docker Hub — tags OpenLiteSpeed : https://hub.docker.com/r/litespeedtech/openlitespeed/tags
- Docker Hub — image WordPress (tags `cli-*`) : https://hub.docker.com/_/wordpress
