# docker-wp-fpm-alpine
Wordpress running with LiteSpeed and PHP 8 inside a Docker container running Alpine with Redis as object cache.

Environment:

```
LS_SOFT_LIMIT=512M
LS_HARD_LIMIT=700M
PHP_MAX_WORKERS=20
WP_VER=latest
WP_PREFIX=wp_
DB_NAME=
DB_USER=
DB_PASSWORD=
DB_PASS=
DB_HOST=localhost
DB_CHARSET=utf8
```

It will download the latest (or the version specified in "WP_VER")

