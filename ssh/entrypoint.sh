#!/bin/bash
set -euo pipefail

USER_NAME=deploy
WEB_UID="${WEB_UID:-65534}"
WEB_GID="${WEB_GID:-65534}"
WP_PATH="${WP_PATH:-/var/www/html}"
HOME_DIR="/home/${USER_NAME}"

if [ -z "${SSH_PUBLIC_KEY:-}" ] && [ -z "${SSH_PASSWORD:-}" ]; then
  echo "ERREUR : définis SSH_PUBLIC_KEY (recommandé) ou SSH_PASSWORD." >&2
  exit 1
fi

# --- Utilisateur aligné sur l'UID/GID du process PHP (fichiers WP modifiables des deux côtés)
getent group "$USER_NAME" >/dev/null || groupadd -o -g "$WEB_GID" "$USER_NAME"
id "$USER_NAME" >/dev/null 2>&1 || useradd -o -u "$WEB_UID" -g "$WEB_GID" -d "$HOME_DIR" -m -s /bin/bash "$USER_NAME"

if [ -n "${SSH_PASSWORD:-}" ]; then
  echo "${USER_NAME}:${SSH_PASSWORD}" | chpasswd
  PW_AUTH=yes
else
  usermod -p '*' "$USER_NAME"   # compte non verrouillé, sans mot de passe (clé uniquement)
  PW_AUTH=no
fi

# --- Clé publique
install -d -m 700 -o "$WEB_UID" -g "$WEB_GID" "$HOME_DIR/.ssh"
printf '%s\n' "${SSH_PUBLIC_KEY:-}" > "$HOME_DIR/.ssh/authorized_keys"
chown "$WEB_UID:$WEB_GID" "$HOME_DIR/.ssh/authorized_keys"
chmod 600 "$HOME_DIR/.ssh/authorized_keys"

# --- Environnement de session (sshd ne transmet pas l'env du conteneur)
cat > "$HOME_DIR/.wp-cli.yml" <<EOF
path: ${WP_PATH}
EOF
mkdir -p "$HOME_DIR/.wp-cli"
cat > "$HOME_DIR/.bashrc" <<EOF
export WP_CLI_CONFIG_PATH=${HOME_DIR}/.wp-cli.yml
cd ${WP_PATH} 2>/dev/null || true
alias ll='ls -lah'
EOF
echo '[ -f ~/.bashrc ] && . ~/.bashrc' > "$HOME_DIR/.bash_profile"
chown -R "$WEB_UID:$WEB_GID" "$HOME_DIR"

# --- Clés d'hôte persistantes (empreinte stable entre redéploiements)
for t in ed25519 rsa; do
  [ -f "/etc/ssh/keys/ssh_host_${t}_key" ] || ssh-keygen -q -t "$t" -N '' -f "/etc/ssh/keys/ssh_host_${t}_key"
done

cat > /etc/ssh/sshd_config <<EOF
Port 22
HostKey /etc/ssh/keys/ssh_host_ed25519_key
HostKey /etc/ssh/keys/ssh_host_rsa_key
PermitRootLogin no
AllowUsers ${USER_NAME}
PubkeyAuthentication yes
PasswordAuthentication ${PW_AUTH}
KbdInteractiveAuthentication no
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 20
X11Forwarding no
# "local" permet un tunnel vers db:3306 (TablePlus, DBeaver...)
AllowTcpForwarding local
Subsystem sftp internal-sftp
EOF

# --- Bootstrap WordPress au premier démarrage
as_user() { HOME="$HOME_DIR" su -p -s /bin/bash "$USER_NAME" -c "$1"; }

mkdir -p "$WP_PATH"
chown "$WEB_UID:$WEB_GID" "$WP_PATH"

if [ ! -f "$WP_PATH/wp-load.php" ]; then
  echo "Téléchargement de WordPress (${WP_LOCALE:-fr_FR})..."
  rm -f "$WP_PATH/index.html"   # page par défaut d'OpenLiteSpeed, prioritaire sur index.php
  as_user 'wp core download --path="$WP_PATH" --locale="${WP_LOCALE:-fr_FR}"'
fi

if [ ! -f "$WP_PATH/wp-config.php" ]; then
  echo "Création de wp-config.php..."
  as_user 'wp config create --path="$WP_PATH" \
      --dbhost="$WORDPRESS_DB_HOST" --dbname="$WORDPRESS_DB_NAME" \
      --dbuser="$WORDPRESS_DB_USER" --dbpass="$WORDPRESS_DB_PASSWORD" \
      --skip-check --extra-php' <<'PHP'
// TLS terminé par le proxy Coolify : on indique à WordPress que la requête d'origine est en HTTPS
if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
    $_SERVER['HTTPS'] = 'on';
}
define('DISALLOW_FILE_EDIT', true);
PHP
fi

echo "SSH prêt (utilisateur: ${USER_NAME}, mot de passe: ${PW_AUTH})"
exec /usr/sbin/sshd -D -e
