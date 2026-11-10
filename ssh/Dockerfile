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

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 22
ENTRYPOINT ["/entrypoint.sh"]
