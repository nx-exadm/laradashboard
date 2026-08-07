# ==============================================================================

# LARADASHBOARD + STARTER26

# Production Docker image for Render

# ==============================================================================

# ==============================================================================

# STAGE 1: BUILD APPLICATION

# ==============================================================================

FROM php:8.3-fpm-alpine AS builder

# ------------------------------------------------------------------------------

# Build dependencies

# ------------------------------------------------------------------------------

RUN apk add --no-cache 
nodejs 
npm 
zip 
unzip 
libzip-dev 
git 
curl

WORKDIR /app

# ------------------------------------------------------------------------------

# Copy Laravel application

# ------------------------------------------------------------------------------

COPY . .

# ------------------------------------------------------------------------------

# Install the REAL Starter26 v1.0.4 ZIP

#

# The repository must contain:

#

# starter26-v1.0.4.zip

#

# ZIP structure:

#

# Starter26/

# app/

# config/

# database/

# dist/

# resources/

# routes/

# module.json

# ...

# ------------------------------------------------------------------------------

RUN set -eux; 
echo "=================================================="; 
echo "Installing Starter26 v1.0.4"; 
echo "=================================================="; 
test -f /app/starter26-v1.0.4.zip; 
mkdir -p /app/modules; 
rm -rf /app/modules/Starter26; 
rm -rf /tmp/starter26-install; 
mkdir -p /tmp/starter26-install; 
unzip -q /app/starter26-v1.0.4.zip -d /tmp/starter26-install; 
test -f /tmp/starter26-install/Starter26/module.json; 
mv /tmp/starter26-install/Starter26 /app/modules/Starter26; 
rm -rf /tmp/starter26-install; 
echo "Starter26 installed successfully."

# ------------------------------------------------------------------------------

# IMPORTANT:

#

# The ZIP contains this demo file:

#

# resources/views/index.blade.php

#

# It contains:

#

# [x-starter26::layouts.master](x-starter26::layouts.master)

#

# But layouts/master.blade.php is a Blade VIEW, not a Blade component class.

#

# Laravel therefore fails during view:cache with:

#

# Unable to locate a class or view for component [starter26::layouts.master]

#

# This demo file is not required by the actual Starter26 frontend.

# Remove it.

# ------------------------------------------------------------------------------

RUN rm -f 
/app/modules/Starter26/resources/views/index.blade.php

# ------------------------------------------------------------------------------

# Verify Starter26 manifest

# ------------------------------------------------------------------------------

RUN set -eux; 
test -f /app/modules/Starter26/module.json; 
echo "Starter26 module.json:"; 
cat /app/modules/Starter26/module.json

# ------------------------------------------------------------------------------

# Verify Starter26 providers

# ------------------------------------------------------------------------------

RUN set -eux; 
test -f /app/modules/Starter26/app/Providers/Starter26ServiceProvider.php; 
test -f /app/modules/Starter26/app/Providers/Starter26LivewireServiceProvider.php; 
echo "Starter26 providers found."

# ------------------------------------------------------------------------------

# Verify compiled Starter26 assets

# ------------------------------------------------------------------------------

RUN set -eux; 
test -f /app/modules/Starter26/dist/build-starter26/manifest.json; 
echo "Starter26 Vite manifest found."; 
find /app/modules/Starter26/dist/build-starter26 -type f | sort

# ==============================================================================

# COMPOSER

# ==============================================================================

COPY --from=composer:2.7 /usr/bin/composer /usr/local/bin/composer

RUN composer install 
--no-interaction 
--prefer-dist 
--optimize-autoloader 
--ignore-platform-reqs

RUN composer dump-autoload 
--optimize 
--no-interaction

# ==============================================================================

# FRONTEND

# ==============================================================================

RUN npm ci

RUN npm run build

# ==============================================================================

# STAGE 2: PRODUCTION

# ==============================================================================

FROM php:8.3-fpm-alpine

# ------------------------------------------------------------------------------

# Production packages

# ------------------------------------------------------------------------------

RUN apk add --no-cache 
nginx 
supervisor 
bash 
postgresql-client 
mariadb-client

# ==============================================================================

# PHP EXTENSIONS

# ==============================================================================

COPY --from=mlocati/php-extension-installer 
/usr/bin/install-php-extensions 
/usr/local/bin/install-php-extensions

RUN chmod +x /usr/local/bin/install-php-extensions 
&& install-php-extensions 
pdo_mysql 
pdo_pgsql 
gd 
zip 
bcmath 
opcache 
mbstring 
openssl 
tokenizer 
xml 
ctype 
json 
fileinfo 
curl

# ==============================================================================

# PHP CONFIGURATION

# ==============================================================================

RUN mv 
"$PHP_INI_DIR/php.ini-production" 
"$PHP_INI_DIR/php.ini"

RUN cat <<'EOF' > "$PHP_INI_DIR/conf.d/production.ini"
opcache.enable=1
opcache.enable_cli=1
opcache.validate_timestamps=0
opcache.memory_consumption=256
opcache.max_accelerated_files=20000

upload_max_filesize=32M
post_max_size=32M
memory_limit=256M
EOF

# ==============================================================================

# APPLICATION

# ==============================================================================

WORKDIR /var/www/html

COPY --from=builder /app /var/www/html

# ==============================================================================

# STARTER26 PERMISSIONS

# ==============================================================================

RUN set -eux; 
test -f /var/www/html/modules/Starter26/app/Providers/Starter26ServiceProvider.php; 
test -f /var/www/html/modules/Starter26/app/Providers/Starter26LivewireServiceProvider.php; 
chown -R www-data:www-data /var/www/html/modules; 
find /var/www/html/modules -type d -exec chmod 755 {} ;; 
find /var/www/html/modules -type f -exec chmod 644 {} ;; 
test -r /var/www/html/modules/Starter26/app/Providers/Starter26ServiceProvider.php; 
test -r /var/www/html/modules/Starter26/app/Providers/Starter26LivewireServiceProvider.php; 
echo "Starter26 providers are readable."

# ==============================================================================

# COPY STARTER26 COMPILED ASSETS INTO PUBLIC

# ==============================================================================

RUN set -eux; 
mkdir -p /var/www/html/public/build-starter26; 
cp -rf 
/var/www/html/modules/Starter26/dist/build-starter26/. 
/var/www/html/public/build-starter26/; 
test -f /var/www/html/public/build-starter26/manifest.json

# ==============================================================================

# REQUIRED LARAVEL DIRECTORIES

# ==============================================================================

RUN mkdir -p 
/var/www/html/storage/app/public 
/var/www/html/storage/framework/cache 
/var/www/html/storage/framework/sessions 
/var/www/html/storage/framework/views 
/var/www/html/storage/logs 
/var/www/html/bootstrap/cache

# ------------------------------------------------------------------------------

# Permissions

# ------------------------------------------------------------------------------

RUN chown -R www-data:www-data 
/var/www/html/storage 
/var/www/html/bootstrap/cache 
/var/www/html/public/build-starter26

RUN chmod -R 775 
/var/www/html/storage 
/var/www/html/bootstrap/cache

# ==============================================================================

# NGINX

# ==============================================================================

RUN mkdir -p /etc/nginx/http.d

RUN cat <<'EOF' > /etc/nginx/http.d/default.conf
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

RUN cat <<'EOF' > /etc/supervisord.conf
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

RUN cat <<'EOF' > /usr/local/bin/entrypoint.sh
#!/bin/sh

set -e

cd /var/www/html

echo ""
echo "=================================================="
echo "LaraDashboard + Starter26"
echo "=================================================="
echo ""

# ==============================================================================

# APP KEY

# ==============================================================================

if [ -z "${APP_KEY:-}" ]; then
echo "ERROR: APP_KEY is missing."
echo "Set APP_KEY in Render Environment Variables."
exit 1
fi

echo "APP_KEY detected."

# ==============================================================================

# .ENV

# ==============================================================================

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

# ==============================================================================

# STARTER26 PERMISSIONS

# ==============================================================================

echo "Applying Starter26 permissions..."

chown -R www-data:www-data /var/www/html/modules

find /var/www/html/modules 
-type d 
-exec chmod 755 {} ;

find /var/www/html/modules 
-type f 
-exec chmod 644 {} ;

# ==============================================================================

# LARAVEL PERMISSIONS

# ==============================================================================

echo "Applying Laravel permissions..."

chown -R www-data:www-data 
/var/www/html/storage 
/var/www/html/bootstrap/cache 
/var/www/html/public/build-starter26

chmod -R 775 
/var/www/html/storage 
/var/www/html/bootstrap/cache

# ==============================================================================

# VERIFY STARTER26

# ==============================================================================

echo ""
echo "=================================================="
echo "STARTER26 CHECK"
echo "=================================================="

test -f 
/var/www/html/modules/Starter26/module.json

test -r 
/var/www/html/modules/Starter26/app/Providers/Starter26ServiceProvider.php

test -r 
/var/www/html/modules/Starter26/app/Providers/Starter26LivewireServiceProvider.php

test -f 
/var/www/html/public/build-starter26/manifest.json

echo "Starter26 module: FOUND"
echo "Starter26 providers: READABLE"
echo "Starter26 assets: FOUND"

# ==============================================================================

# CLEAR CACHES

# ==============================================================================

echo ""
echo "Clearing Laravel caches..."

php artisan optimize:clear

# ==============================================================================

# MODULE STATUS

# ==============================================================================

echo ""
echo "=================================================="
echo "MODULE STATUS"
echo "=================================================="

php artisan module:list || true

# ==============================================================================

# CONFIG CACHE

# ==============================================================================

echo ""
echo "Caching Laravel configuration..."

php artisan config:cache

# ==============================================================================

# ROUTE CACHE

# ==============================================================================

echo ""
echo "Caching Laravel routes..."

php artisan route:cache

# ==============================================================================

# VIEW CACHE

# ==============================================================================

echo ""
echo "Caching Laravel views..."

php artisan view:cache

# ==============================================================================

# STORAGE LINK

# ==============================================================================

echo ""
echo "Creating storage link..."

php artisan storage:link --force || true

# ==============================================================================

# FINAL PERMISSIONS

# ==============================================================================

chown -R www-data:www-data 
/var/www/html/modules 
/var/www/html/storage 
/var/www/html/bootstrap/cache 
/var/www/html/public/build-starter26

find /var/www/html/modules 
-type d 
-exec chmod 755 {} ;

find /var/www/html/modules 
-type f 
-exec chmod 644 {} ;

chmod -R 775 
/var/www/html/storage 
/var/www/html/bootstrap/cache

# ==============================================================================

# START

# ==============================================================================

echo ""
echo "=================================================="
echo "Starting Nginx + PHP-FPM"
echo "=================================================="
echo ""

exec /usr/bin/supervisord -c /etc/supervisord.conf
EOF

RUN chmod +x /usr/local/bin/entrypoint.sh

# ==============================================================================

# RENDER

# ==============================================================================

EXPOSE 80

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
