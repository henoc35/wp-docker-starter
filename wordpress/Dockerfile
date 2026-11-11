# Image OpenLiteSpeed officielle + réglages PHP pilotés par variables d'environnement.
# Construite avec le contexte à la racine du dépôt (voir docker-compose.yml).
ARG OLS_TAG=1.8.5-lsphp85
FROM litespeedtech/openlitespeed:${OLS_TAG}

COPY php/php-env.sh /usr/local/bin/php-env.sh
COPY wordpress/php-entrypoint.sh /php-entrypoint.sh
RUN chmod +x /usr/local/bin/php-env.sh /php-entrypoint.sh

ENTRYPOINT ["/php-entrypoint.sh"]
