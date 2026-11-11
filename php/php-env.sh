#!/bin/sh
# Génère des directives php.ini à partir des variables d'environnement.
# Usage : php-env.sh web   -> réglages du PHP qui sert le site (lsphp / OpenLiteSpeed)
#         php-env.sh cli   -> réglages du PHP de WP-CLI (conteneur ssh)
# Une variable vide ou absente prend la valeur par défaut indiquée.
set -eu

mode="${1:-web}"

case "$mode" in
  web)
    cat <<INI
memory_limit = ${PHP_MEMORY_LIMIT:-512M}
upload_max_filesize = ${PHP_UPLOAD_MAX_FILESIZE:-128M}
post_max_size = ${PHP_POST_MAX_SIZE:-128M}
max_execution_time = ${PHP_MAX_EXECUTION_TIME:-300}
max_input_time = ${PHP_MAX_INPUT_TIME:-300}
max_input_vars = ${PHP_MAX_INPUT_VARS:-5000}
max_file_uploads = ${PHP_MAX_FILE_UPLOADS:-50}
date.timezone = ${PHP_DATE_TIMEZONE:-UTC}
display_errors = ${PHP_DISPLAY_ERRORS:-Off}
log_errors = On
error_reporting = ${PHP_ERROR_REPORTING:-E_ALL & ~E_DEPRECATED}
expose_php = Off
realpath_cache_size = ${PHP_REALPATH_CACHE_SIZE:-4096K}
realpath_cache_ttl = 600
session.gc_maxlifetime = ${PHP_SESSION_GC_MAXLIFETIME:-1440}
opcache.enable = ${PHP_OPCACHE_ENABLE:-1}
opcache.memory_consumption = ${PHP_OPCACHE_MEMORY_CONSUMPTION:-256}
opcache.interned_strings_buffer = ${PHP_OPCACHE_INTERNED_STRINGS_BUFFER:-16}
opcache.max_accelerated_files = ${PHP_OPCACHE_MAX_ACCELERATED_FILES:-20000}
opcache.validate_timestamps = ${PHP_OPCACHE_VALIDATE_TIMESTAMPS:-1}
opcache.revalidate_freq = ${PHP_OPCACHE_REVALIDATE_FREQ:-2}
INI
    ;;
  cli)
    cat <<INI
memory_limit = ${WPCLI_MEMORY_LIMIT:-512M}
date.timezone = ${PHP_DATE_TIMEZONE:-UTC}
INI
    ;;
  *)
    echo "php-env.sh : mode inconnu '$mode' (web|cli)" >&2
    exit 1
    ;;
esac

# Directives libres, une par ligne (ex. "opcache.jit = tracing")
if [ -n "${PHP_EXTRA_INI:-}" ]; then
  printf '%s\n' "$PHP_EXTRA_INI"
fi
