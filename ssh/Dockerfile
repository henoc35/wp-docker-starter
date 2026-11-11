# Construite avec le contexte à la racine du dépôt (voir docker-compose.yml).
ARG PHP_VERSION=8.5
FROM wordpress:cli-php${PHP_VERSION}

USER root

RUN apk add --no-cache \
      openssh-server \
      bash \
      shadow \
      mariadb-client \
      redis \
      rsync \
      nano \
      less \
    && mkdir -p /etc/ssh/keys /run/sshd

COPY php/php-env.sh /usr/local/bin/php-env.sh
COPY ssh/entrypoint.sh /entrypoint.sh
RUN chmod +x /usr/local/bin/php-env.sh /entrypoint.sh

EXPOSE 22
ENTRYPOINT ["/entrypoint.sh"]
