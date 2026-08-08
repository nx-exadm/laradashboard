# ==============================================================================

# LARADASHBOARD + STARTER26 + FORUM

# ==============================================================================

FROM php:8.3-fpm-alpine AS builder

WORKDIR /app

# Build dependencies

RUN apk add --no-cache nodejs npm zip unzip libzip-dev git curl

# Copy application

COPY . .

# ==============================================================================

# STARTER26

# ==============================================================================

RUN set -eux; 
test -f /app/starter26-v1.0.4.zip; 
mkdir -p /app/modules; 
rm -rf /app/modules/Starter26; 
mkdir -p /tmp/starter26-install; 
unzip -q /app/starter26-v1.0.4.zip -d /tmp/starter26-install; 
if [ -f /tmp/starter26-install/Starter26/module.json ]; then 
mv /tmp/starter26-install/Starter26 /app/modules/Starter26; 
elif [ -f /tmp/starter26-install/module.json ]; then 
mv /tmp/starter26-install /app/modules/Starter26; 
else 
echo "ERROR: Starter26 module.json not found"; 
find /tmp/starter26-install -maxdepth 4 -type f | sort; 
exit 1; 
fi; 
rm -f /app/starter26-v1.0.4.zip

# ==============================================================================

# FORUM

# ==============================================================================

RUN set -eux; 
test -f /app/forum-v0.1.3.zip; 
mkdir -p /app/modules; 
rm -rf /app/modules/Forum; 
mkdir -p /tmp/forum-install; 
unzip -q /app/forum-v0.1.3.zip -d /tmp/forum-install; 
if [ -f /tmp/forum-install/Forum/module.json ]; then 
mv /tmp/forum-install/Forum /app/modules/Forum; 
elif [ -f /tmp/forum-install/module.json ]; then 
mv /tmp/forum-install /app/modules/Forum; 
else 
echo "ERROR: Forum module.json not found"; 
find /tmp/forum-install -maxdepth 5 -type f | sort; 
exit 1; 
fi; 
rm -f /app/forum-v0.1.3.zip

# ==============================================================================

# VERIFY MODULES

# ==============================================================================

RUN set -eux; 
test -f /app/modules/Starter26/module.json; 
test -f /app/modules/Forum/module.json; 
echo "Starter26: OK"; 
echo "Forum: OK"

# ==============================================================================

# COMPOSER

# ==============================================================================

COPY --from=composer:2.7 /usr/bin/composer /usr/local/bin/composer

RUN composer install --no-interaction --prefer-dist --optimize-autoloader --ignore-platform-reqs

RUN composer dump-autoload --optimize --no-interaction

# ==============================================================================

# USE PREBUILT MODULE ASSETS

# ==============================================================================

RUN set -eux; 
test -f /app/modules/Starter26/dist/build-starter26/manifest.json; 
mkdir -p /app/public/build-starter26; 
cp -R /app/modules/Starter26/dist/build-starter26/. /app/public/build-starter26/; 
test -f /app/public/build-starter26/manifest.json; 
echo "Starter26 assets: OK"

RUN set -eux; 
test -f /app/modules/Forum/dist/build-forum/manifest.json; 
mkdir -p /app/public/build-forum; 
cp -R /app/modules/Forum/dist/build-forum/. /app/public/build-forum/; 
test -f /app/public/build-forum/manifest.json; 
echo "Forum assets: OK"

# ==============================================================================

# PRODUCTION

# ==============================================================================

FROM php:8.3-fpm-alpine

RUN apk add --no-cache nginx supervisor bash postgresql-client mariadb-client unzip

COPY --from=mlocati/php-extension-installer /usr/bin/install-php-extensions /usr/local/bin/install-php-extensions

RUN chmod +x /usr/local/bin/install-php-extensions 
&& install-php-extensions pdo_mysql pdo_pgsql gd zip bcmath opcache mbstring openssl tokenizer xml ctype json fileinfo curl

RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

RUN printf '%s\n' 
'opcache.enable=1' 
'opcache.enable_cli=1' 
'opcache.validate_timestamps=0' 
'opcache.memory_consumption=256' 
'opcache.max_accelerated_files=20000' 
'upload_max_filesize=32M' 
'post_max_size=32M' 
'memory_limit=256M' 
> "$PHP_INI_DIR/conf.d/production.ini"

WORKDIR /var/www/html

COPY --from=builder /app /var/www/html

RUN mkdir -p 
/var/www/html/storage/app/public 
/var/www/html/storage/framework/cache 
/var/www/html/storage/framework/sessions 
/var/www/html/storage/framework/views 
/var/www/html/storage/logs 
/var/www/html/bootstrap/cache

RUN chown -R www-data:www-data /var/www/html 
&& find /var/www/html -type d -exec chmod 755 {} ; 
&& find /var/www/html -type f -exec chmod 644 {} ; 
&& chmod -R 775 /var/www/html/storage 
&& chmod -R 775 /var/www/html/bootstrap/cache 
&& chmod +x /var/www/html/artisan

# ==============================================================================

# FINAL CHECK

# ==============================================================================

RUN set -eux; 
test -f /var/www/html/modules/Starter26/module.json; 
test -f /var/www/html/modules/Forum/module.json; 
test -f /var/www/html/public/build-starter26/manifest.json; 
test -f /var/www/html/public/build-forum/manifest.json; 
echo "======================================"; 
echo "STARTER26 + FORUM BUILD CHECK PASSED"; 
echo "======================================"

# ==============================================================================

# NGINX

# ==============================================================================

RUN mkdir -p /etc/nginx/http.d

RUN cat > /etc/nginx/http.d/default.conf <<'EOF'
server {
listen 80 default_server;
server_name _;

```
root /var/www/html/public;

index index.php index.html;

charset utf-8;

location / {
    try_files $uri $uri/ /index.php?$query_string;
}

location ~ \.php$ {
    try_files $uri =404;

    fastcgi_pass 127.0.0.1:9000;
    fastcgi_index index.php;

    include fastcgi_params;

    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    fastcgi_param DOCUMENT_ROOT $document_root;
}

location ~ /\.ht {
    deny all;
}
```

}
EOF

# ==============================================================================

# SUPERVISOR

# ==============================================================================

RUN cat > /etc/supervisord.conf <<'EOF'
[supervisord]
nodaemon=true
user=root
logfile=/dev/null
pidfile=/var/run/supervisord.pid

[program:php-fpm]
command=php-fpm -F
priority=10
autostart=true
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
stopasgroup=true
killasgroup=true

[program:nginx]
command=nginx -g "daemon off;"
priority=20
autostart=true
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
stopasgroup=true
killasgroup=true
EOF

# ==============================================================================

# ENTRYPOINT

# ==============================================================================

RUN cat > /usr/local/bin/entrypoint.sh <<'EOF'
#!/bin/sh

set -e

cd /var/www/html

echo "=================================================="
echo "LaraDashboard + Starter26 + Forum"
echo "=================================================="

PORT="${PORT:-80}"

echo "Render port: ${PORT}"

sed -i "s/listen 80 default_server;/listen ${PORT} default_server;/" 
/etc/nginx/http.d/default.conf

if [ -z "${APP_KEY:-}" ]; then
echo "ERROR: APP_KEY is missing."
exit 1
fi

if [ ! -f /var/www/html/.env ]; then
if [ -f /var/www/html/.env.example ]; then
cp /var/www/html/.env.example /var/www/html/.env
else
touch /var/www/html/.env
fi
fi

if grep -q '^APP_KEY=' /var/www/html/.env; then
sed -i "s|^APP_KEY=.*|APP_KEY=${APP_KEY}|" /var/www/html/.env
else
echo "APP_KEY=${APP_KEY}" >> /var/www/html/.env
fi

chown -R www-data:www-data 
/var/www/html/storage 
/var/www/html/bootstrap/cache

chmod -R 775 
/var/www/html/storage 
/var/www/html/bootstrap/cache

echo "Checking Starter26..."
test -f /var/www/html/modules/Starter26/module.json
test -f /var/www/html/public/build-starter26/manifest.json

echo "Checking Forum..."
test -f /var/www/html/modules/Forum/module.json
test -f /var/www/html/public/build-forum/manifest.json

echo "Clearing Laravel caches..."
php artisan optimize:clear

echo "Running migrations..."
php artisan migrate --force

echo "Module list:"
php artisan module:list || true

echo "Caching config..."
php artisan config:cache

echo "Caching routes..."
php artisan route:cache

echo "Caching views..."
php artisan view:cache

echo "Creating storage link..."
php artisan storage:link --force || true

chown -R www-data:www-data 
/var/www/html/storage 
/var/www/html/bootstrap/cache

chmod -R 775 
/var/www/html/storage 
/var/www/html/bootstrap/cache

echo "=================================================="
echo "STARTING NGINX + PHP-FPM"
echo "=================================================="

exec /usr/bin/supervisord -c /etc/supervisord.conf
EOF

RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 80

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
