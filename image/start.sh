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
					if [[ "$HTTPS_DOMAIN" != "" ]]; then
						patch -u "$settings" -i /var/www/wp-config.patch
						# HTTPS Rules
						sed -i "s/HTTPS_DOMAIN/$HTTPS_DOMAIN/" $settings
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

# Remove Example data
rm -rf "$ls_root/Example"
rm -rf "$ls_root/conf/vhosts/Example"
rm -rf "$ls_root/logs/Example"

apk del patch
"$ls_root/bin/lswsctrl" start
#while pgrep litespeed > /dev/null; do
tail -f /var/log/litespeed/error.log
#done
