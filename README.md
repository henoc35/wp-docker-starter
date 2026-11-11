# Starter WordPress pour Coolify

OpenLiteSpeed 1.8.5 (PHP 8.5) + LiteSpeed Cache, MariaDB 10.11, Redis 7, conteneur SSH/SFTP/WP-CLI
accessible via un tunnel Cloudflare (aucun port public). Réglages PHP et constantes WordPress
pilotés par variables d'environnement.

👉 **Procédure complète pas à pas : [GUIDE.md](GUIDE.md)** (clé SSH, jeton Cloudflare, variables,
déploiement, connexion, installation WordPress, dépannage).

## Structure

```
docker-compose.yml           # stack complète
wordpress/Dockerfile         # OpenLiteSpeed + application des réglages PHP au démarrage
wordpress/php-entrypoint.sh  # écrit les variables PHP_* dans le php.ini de lsphp
ssh/Dockerfile               # image SSH + WP-CLI (basée sur wordpress:cli-php8.5)
ssh/entrypoint.sh            # utilisateur deploy, sshd, bootstrap WordPress, constantes wp-config
php/php-env.sh               # génération des directives php.ini (partagé par les deux images)
.env.example                 # toutes les variables, avec exemples
GUIDE.md                     # documentation de bout en bout
```

## Résumé express

1. Générer une clé SSH : `ssh-keygen -t ed25519` (ou utiliser `SSH_PASSWORD`).
2. Créer un tunnel Cloudflare (**Networking > Tunnels > Create a tunnel**) et copier le jeton `eyJ...`.
3. Pousser ce dossier dans un dépôt Git et créer une ressource Docker Compose dans Coolify.
4. Renseigner `SSH_PUBLIC_KEY` (ou `SSH_PASSWORD`) et `CLOUDFLARE_TUNNEL_TOKEN`, attribuer le domaine à `wordpress` (port 80), déployer.
5. Dans le tunnel : **Routes > Add route > Published application**, service **SSH** → `ssh:22`.
6. Poste client : `cloudflared` + `ProxyCommand cloudflared access ssh --hostname %h` dans `~/.ssh/config`.
7. En SSH : `wp core install ...`, puis LiteSpeed Cache + Redis.
8. Ajuster au besoin les variables `PHP_*`, `WP_*`, `WPCLI_MEMORY_LIMIT`, `REDIS_MAXMEMORY` (GUIDE.md, section 13).
