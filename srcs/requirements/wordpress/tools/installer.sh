#!/bin/bash

# Si WordPress est déjà installé, ne refais pas toute l'installation
if [ -f /var/www/html/wp-config.php ]; then
#	echo "WordPress déjà installé. Démarrage de PHP-FPM."
	exec php-fpm7.4 -F
fi

# Téléchargement de wp-cli
wget https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
mv wp-cli.phar /usr/local/bin/wp

# Donne les bons droits au dossier WordPress
chown -R www-data:www-data /var/www/
chmod -R 755 /var/www/

# Attendre que MariaDB soit prêt
until mysqladmin --silent --host="$WORDPRESS_DB_HOST" ping; do
#  echo "En attente de MariaDB..."
  sleep 2
done

# Exécuter le reste en tant que www-data
su -s /bin/bash www-data << EOF

cd /var/www/html

# Télécharger WordPress
wp core download

# Créer wp-config.php
wp core config \
  --dbname=$MYSQL_DATABASE \
  --dbuser=$MYSQL_USER \
  --dbpass=$MYSQL_PASSWORD \
  --dbhost=$WORDPRESS_DB_HOST

# Ajouter les infos Redis
wp config set WP_REDIS_HOST $REDIS_HOST
wp config set WP_REDIS_PORT $REDIS_PORT

# Installer WordPress (site + admin)
wp core install \
  --url=$DOMAIN \
  --title="Inception" \
  --admin_user=$WP_ADMIN_USER \
  --admin_password=$WP_ADMIN_PASSWORD \
  --admin_email=$WP_ADMIN_EMAIL

# Créer un utilisateur secondaire
wp user create $WP_USER $WP_EMAIL --role=author --user_pass=$WP_PASSWORD

# Installer et activer Redis Cache
wp plugin install redis-cache --activate
wp redis enable

EOF

# Lancer PHP-FPM au premier plan
exec php-fpm7.4 -F

