#!/bin/bash
# Applique les réglages PHP issus des variables d'environnement, puis lance
# l'entrypoint d'origine de l'image OpenLiteSpeed.
set -euo pipefail
shopt -s nullglob

BEGIN='; >>> starter-env >>>'
END='; <<< starter-env <<<'

found=0
for ini in /usr/local/lsws/lsphp*/etc/php/*/litespeed/php.ini; do
  found=1
  # Supprime le bloc précédent (idempotent), puis ajoute le nouveau en fin de fichier :
  # dans un php.ini, la dernière occurrence d'une directive l'emporte.
  sed -i "/^${BEGIN}\$/,/^${END}\$/d" "$ini"
  {
    echo "$BEGIN"
    /usr/local/bin/php-env.sh web
    echo "$END"
  } >> "$ini"
  echo "Réglages PHP appliqués : $ini"
done

if [ "$found" -eq 0 ]; then
  echo "AVERTISSEMENT : aucun php.ini lsphp trouvé, réglages PHP non appliqués." >&2
fi

exec /entrypoint.sh "$@"
