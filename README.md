# Starter WordPress pour Coolify

OpenLiteSpeed 1.8.5 (PHP 8.5) + LiteSpeed Cache, MariaDB 10.11, Redis 7, conteneur SSH/SFTP/WP-CLI
accessible via un tunnel Cloudflare (aucun port public).

👉 **Procédure complète pas à pas : [GUIDE.md](GUIDE.md)** (clé SSH, jeton Cloudflare, variables,
déploiement, connexion, installation WordPress, dépannage).

## Structure

```
docker-compose.yml   # stack complète
ssh/Dockerfile       # image SSH + WP-CLI (basée sur wordpress:cli-php8.5)
ssh/entrypoint.sh    # utilisateur deploy, sshd, bootstrap WordPress
.env.example         # variables à renseigner dans Coolify (avec exemples)
GUIDE.md             # documentation de bout en bout
```

## Résumé express

1. Générer une clé SSH : `ssh-keygen -t ed25519`.
2. Créer un tunnel Cloudflare (**Networking > Tunnels > Create a tunnel**) et copier le jeton `eyJ...`.
3. Pousser ce dossier dans un dépôt Git et créer une ressource Docker Compose dans Coolify.
4. Renseigner `SSH_PUBLIC_KEY` et `CLOUDFLARE_TUNNEL_TOKEN`, attribuer le domaine à `wordpress`, déployer.
5. Dans le tunnel : **Routes > Add route > Published application**, service **SSH** → `ssh:22`.
6. Poste client : `cloudflared` + `ProxyCommand cloudflared access ssh --hostname %h` dans `~/.ssh/config`.
7. En SSH : `wp core install ...`, puis LiteSpeed Cache + Redis.
