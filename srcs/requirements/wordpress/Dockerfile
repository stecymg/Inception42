FROM debian:bullseye

RUN apt-get update && apt-get install -y \
    php \
    php7.4-fpm \
    php-mysqli \
    php-redis \
    mariadb-client \
    curl \
    wget \
    less \
    vim \
    unzip \
    default-mysql-client && \
    apt-get clean

#Crée les dossier
RUN mkdir -p /workspace /run/php

#Sélect le dossier de travail
WORKDIR /workspace

#Copie des fichiers de config et du script
COPY ./conf/www.conf /etc/php/7.4/fpm/pool.d/www.conf
COPY ./tools/installer.sh .
RUN chmod +x installer.sh

#Lance le script à l'exécution du conteneur
CMD ["./installer.sh"]

