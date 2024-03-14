#!/bin/bash
echo "Starting..."
case $OBJ_CACHE in
	"memcached" )
		apk add --update --no-cache memcached php$PHP_VER-pecl-memcached
		memcached -d -u litespeed
		rm -rf /var/cache/apk/*
	;;
	"redis" )
		apk add --update --no-cache redis
		redis-server &
		rm -rf /var/cache/apk/*
	;;
esac

install=false
if [[ -f /var/www/wp-config.php ]]; then
	curr_ver=$(awk '/^\$wp_version/ { print $3 }' /var/www/wp-includes/version.php | sed "s/[';]//g")
	last_ver=$(curl -s "https://api.wordpress.org/core/version-check/1.7/" | grep -oE 'wordpress-[0-9.]+.zip' | head -n1 | sed -nr 's/.*wordpress-([0-9.]+)\.zip.*/\1/p')
	if [[ "$curr_ver" != "$WP_VER" && "$curr_ver" != "$last_ver" ]]; then
		echo "Updating Wordpress from $curr_ver to $WP_VER..."
		install=true
	fi
else
	echo "Wordpress not found. Installing Wordpress. Version: $WP_VER"
	install=true
fi
if [[ $install == true ]]; then
	HYPHEN=""
	SUBDOM=""
	if [[ "$WP_LANG" != "" ]]; then
		HYPHEN="-${WP_LANG}"
		SUBDOM="${WP_LANG}."
	fi
	# Install Wordpress
	sha1=$(curl -s "https://${SUBDOM}wordpress.org/wordpress-${WP_VER}${HYPHEN}.tar.gz.sha1"); 
	wpurl="https://${SUBDOM}wordpress.org/wordpress-${WP_VER}${HYPHEN}.tar.gz"
	echo "Downloading from: $wpurl ..."
	curl -o wordpress.tar.gz -fL $wpurl
	if echo "$sha1 *wordpress.tar.gz" | sha1sum -c -; then
		if tar -xzf wordpress.tar.gz -C /tmp/; then
			rm wordpress.tar.gz; 
			if chown -R litespeed.litespeed /tmp/wordpress/; then
				if [[ -f /var/www/wp-config.php ]]; then
					rm /tmp/wp-config*
					if ! rsync -ia /tmp/wordpress/ /var/www/; then
						echo "Failed to copy wp-content"
						exit 3
					fi
				else
					rsync -ia /tmp/wordpress/ /var/www/;
					settings="/var/www/wp-config-sample.php"
					patch -u "$settings" -i /var/www/wp-config.patch
					#TMP: backward compatibility:
					if [[ "$HTTPS_DOMAIN" != "" ]]; then
						DOMAIN="$HTTPS_DOMAIN";
						HTTPS="true";
					fi
					if [[ "$DOMAIN" != "" ]]; then
						sed -i "s/DOMAIN/$DOMAIN/" $settings
						sed -i "s/=HTTPS/=$HTTPS/" $settings
					else # If domain is not specified, remove header code
						sed -i -e 1,8d $settings
					fi
					rm /var/www/wp-config.patch

					# DB_NAME
					sed -i "s/database_name_here/$DB_NAME/" $settings
					# DB_USER
					sed -i "s/username_here/$DB_USER/" $settings
					# DB_PASSWORD
					sed -i "s/password_here/${DB_PASS:-$DB_PASSWORD}/" $settings
					# DB_HOST
					sed -i "s/localhost/${DB_HOST}/" $settings
					# DB_PORT
					sed -i "s/ 3306 / ${DB_PORT:-3306} /" $settings
					# DB_SSL
					sed -i "s/db_ssl_enabled/${DB_SSL}/" $settings
					# DB_CHARSET
					sed -i "s/utf8/${DB_CHARSET}/" $settings
					# WP_PREFIX
					sed -i "s/'wp_'/'${WP_PREFIX}'/" $settings
					# Keys: (sed in alpine needs to match somehow an index in order to replace once)
					for j in {50..65}; do
						KEY=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 64 ; echo '')
						sed -i "$j,/put your unique phrase here/{s/put your unique phrase here/$KEY/}" $settings
					done
					mv $settings /var/www/wp-config.php
				fi
				rm -rf /tmp/wordpress/
			else
				echo "Unable to set permissions in tmp"
				exit 2
			fi
		fi
	else
		echo "Wordpress fingerprint failed."
		exit 1
	fi
fi

# LiteSpeed setup:
echo "Starting litespeed...."
ls_root="/var/lib/litespeed"
ls_conf="/etc/litespeed/httpd_config.conf"
patch -u "$ls_conf" -i /etc/litespeed/httpd_config.patch
rm /etc/litespeed/httpd_config.patch
sed -i "s/SOFT_LIMIT/$LS_SOFT_LIMIT/g" "$ls_conf"
sed -i "s/HARD_LIMIT/$LS_HARD_LIMIT/g" "$ls_conf"
mkdir -p "$ls_root/sessions/"
chown litespeed.litespeed "$ls_root/sessions/"

# PHP setup:
php_ini="/etc/php${PHP_VER}/php.ini"
sed -i "s/upload_max_filesize = 2M/upload_max_filesize = $PHP_MAX_UPLOAD/" "$php_ini"
sed -i "s/post_max_size = 8M/post_max_size = $PHP_MAX_UPLOAD/" "$php_ini"

# Remove Example data
rm -rf "$ls_root/Example"
rm -rf "$ls_root/conf/vhosts/Example"
rm -rf "$ls_root/logs/Example"

init_script=${INIT_SCRIPT:-"/home/init.sh"}
if [[ ! -f $init_script ]]; then
	init_script="/var/www/wp-content/init.sh";
fi
if [[ -f "$init_script" ]]; then
	echo "Starting custom script..."
	chmod +rx "$init_script"
	bash "$init_script"
	chmod -rwx "$init_script"
	echo "Custom script executed."
else
	echo "INFO: You can customize this site by adding 'init.sh' script under 'wp-content' directory";
fi

# Lock root:
chown root.root /var/www/
chown root.root /var/www/*
chown litespeed.litespeed /var/www/wp-content/

# Clean up:
rm -rf /var/www/wp-content/plugins/hello.php

apk del patch
"$ls_root/bin/lswsctrl" start
#while pgrep litespeed > /dev/null; do
tail -f /var/log/litespeed/error.log
#done
