```dockerfile
# ==============================================================================
# LARADASHBOARD + STARTER26
# Production Docker image for Render
# ==============================================================================


# ==============================================================================
# STAGE 1: BUILD APPLICATION
# ==============================================================================

FROM php:8.3-fpm-alpine AS builder


# ==============================================================================
# BUILD DEPENDENCIES
# ==============================================================================

RUN apk add --no-cache \
    nodejs \
    npm \
    zip \
    unzip \
    libzip-dev \
    git \
    curl


WORKDIR /app


# ==============================================================================
# COPY LARAVEL APPLICATION
# ==============================================================================

COPY . .


# ==============================================================================
# INSTALL REAL STARTER26 MODULE FROM ZIP
# ==============================================================================

RUN echo "==================================================" \
    && echo "Installing Starter26 v1.0.4" \
    && echo "==================================================" \
    && test -f /app/starter26-v1.0.4.zip \
    && mkdir -p /app/modules \
    && rm -rf /app/modules/Starter26 \
    && mkdir -p /tmp/starter26-install \
    && unzip -q /app/starter26-v1.0.4.zip \
        -d /tmp/starter26-install \
    && test -f /tmp/starter26-install/Starter26/module.json \
    && mv /tmp/starter26-install/Starter26 \
        /app/modules/Starter26 \
    && rm -rf /tmp/starter26-install \
    && echo "Starter26 installed successfully."


# ==============================================================================
# VERIFY STARTER26 MODULE
# ==============================================================================

RUN echo "==================================================" \
    && echo "STARTER26 MODULE MANIFEST" \
    && echo "==================================================" \
    && test -f /app/modules/Starter26/module.json \
    && cat /app/modules/Starter26/module.json


# ==============================================================================
# VERIFY STARTER26 PRECOMPILED ASSETS
# ==============================================================================

RUN echo "==================================================" \
    && echo "STARTER26 PRECOMPILED ASSETS" \
    && echo "==================================================" \
    && test -f /app/modules/Starter26/dist/build-starter26/manifest.json \
    && find /app/modules/Starter26/dist/build-starter26 \
        -type f \
        | sort


# ==============================================================================
# REMOVE BROKEN UNUSED DEMO VIEW
#
# The ZIP contains:
#
# resources/views/index.blade.php
#
# which references:
#
# <x-starter26::layouts.master>
#
# while master.blade.php is located under:
#
# resources/views/layouts/master.blade.php
#
# The actual Starter26 frontend does not require this demo view.
# Removing it prevents Laravel view:cache from attempting to compile it.
# ==============================================================================

RUN rm -f \
    /app/modules/Starter26/resources/views/index.blade.php


# ==============================================================================
# COMPOSER
# ==============================================================================

COPY --from=composer:2.7 \
    /usr/bin/composer \
    /usr/local/bin/composer


# ==============================================================================
# INSTALL PHP DEPENDENCIES
# ==============================================================================

RUN composer install \
    --no-interaction \
    --prefer-dist \
    --optimize-autoloader \
    --ignore-platform-reqs


# ==============================================================================
# REBUILD COMPOSER AUTOLOAD
# ==============================================================================

RUN composer dump-autoload \
    --optimize \
    --no-interaction


# ==============================================================================
# MAIN FRONTEND
# ==============================================================================

RUN npm ci

RUN npm run build


# ==============================================================================
# STAGE 2: PRODUCTION
# ==============================================================================

FROM php:8.3-fpm-alpine


# ==============================================================================
# PRODUCTION PACKAGES
# ==============================================================================

RUN apk add --no-cache \
    nginx \
    supervisor \
    bash \
    postgresql-client \
    mariadb-client


# ==============================================================================
# PHP EXTENSIONS
# ==============================================================================

COPY --from=mlocati/php-extension-installer \
    /usr/bin/install-php-extensions \
    /usr/local/bin/install-php-extensions


RUN chmod +x \
    /usr/local/bin/install-php-extensions \
    && install-php-extensions \
        pdo_mysql \
        pdo_pgsql \
        gd \
        zip \
        bcmath \
        opcache \
        mbstring \
        openssl \
        tokenizer \
        xml \
        ctype \
        json \
        fileinfo \
        curl


# ==============================================================================
# PHP PRODUCTION CONFIGURATION
# ==============================================================================

RUN mv \
    "$PHP_INI_DIR/php.ini-production" \
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
# CRITICAL: FIX MODULE PERMISSIONS
#
# PHP-FPM runs as www-data.
#
# Laravel dynamically loads:
#
# modules/Starter26/app/Providers/Starter26ServiceProvider.php
#
# which loads:
#
# modules/Starter26/app/Providers/Starter26LivewireServiceProvider.php
#
# Therefore PHP must be able to traverse every module directory and read
# every PHP file.
# ==============================================================================

RUN chown -R www-data:www-data \
        /var/www/html/modules \
    && find /var/www/html/modules \
        -type d \
        -exec chmod 755 {} \; \
    && find /var/www/html/modules \
        -type f \
        -exec chmod 644 {} \;


# ==============================================================================
# VERIFY STARTER26 PHP PROVIDERS ARE READABLE
# ==============================================================================

RUN test -r \
        /var/www/html/modules/Starter26/app/Providers/Starter26ServiceProvider.php \
    && test -r \
        /var/www/html/modules/Starter26/app/Providers/Starter26LivewireServiceProvider.php \
    && echo "Starter26 PHP providers are readable."


# ==============================================================================
# INSTALL STARTER26 PRECOMPILED VITE ASSETS
#
# The ZIP contains:
#
# modules/Starter26/dist/build-starter26/
#
# Laravel's @vite(..., 'build-starter26') expects the compiled build to be
# available under public/build-starter26.
# ==============================================================================

RUN mkdir -p \
        /var/www/html/public/build-starter26 \
    && cp -rf \
        /var/www/html/modules/Starter26/dist/build-starter26/* \
        /var/www/html/public/build-starter26/


# ==============================================================================
# VERIFY STARTER26 ASSETS IN PUBLIC
# ==============================================================================

RUN echo "==================================================" \
    && echo "FINAL STARTER26 ASSET CHECK" \
    && echo "==================================================" \
    && test -f \
        /var/www/html/public/build-starter26/manifest.json \
    && echo "Starter26 Vite manifest: FOUND" \
    && find /var/www/html/public/build-starter26 \
        -maxdepth 2 \
        -type f \
        | sort


# ==============================================================================
# CREATE REQUIRED LARAVEL DIRECTORIES
# ==============================================================================

RUN mkdir -p \
    /var/www/html/storage/app/public \
    /var/www/html/storage/framework/cache \
    /var/www/html/storage/framework/sessions \
    /var/www/html/storage/framework/views \
    /var/www/html/storage/logs \
    /var/www/html/bootstrap/cache \
    /var/www/html/public/build-starter26


# ==============================================================================
# STORAGE / CACHE / PUBLIC ASSET PERMISSIONS
# ==============================================================================

RUN chown -R www-data:www-data \
        /var/www/html/storage \
        /var/www/html/bootstrap/cache \
        /var/www/html/public/build-starter26 \
    && chmod -R 775 \
        /var/www/html/storage \
        /var/www/html/bootstrap/cache


# ==============================================================================
# NGINX CONFIGURATION
# ==============================================================================

RUN mkdir -p /etc/nginx/http.d


RUN cat <<'EOF' > /etc/nginx/http.d/default.conf

server {
    listen 80 default_server;
    server_name _;

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
}

EOF


# ==============================================================================
# SUPERVISOR CONFIGURATION
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
echo "LaraDashboard Production Startup"
echo "=================================================="
echo ""


# ==============================================================================
# APP KEY
# ==============================================================================

if [ -z "${APP_KEY:-}" ]; then

    echo ""
    echo "ERROR: APP_KEY is missing."
    echo ""
    echo "Set APP_KEY in Render Environment Variables."
    echo ""

    exit 1

fi


echo "APP_KEY detected."


# ==============================================================================
# CREATE .ENV IF NECESSARY
# ==============================================================================

if [ ! -f /var/www/html/.env ]; then

    if [ -f /var/www/html/.env.example ]; then

        cp /var/www/html/.env.example /var/www/html/.env

    else

        touch /var/www/html/.env

    fi

fi


# ==============================================================================
# WRITE APP KEY TO .ENV
# ==============================================================================

if grep -q '^APP_KEY=' /var/www/html/.env; then

    sed -i \
        "s|^APP_KEY=.*|APP_KEY=${APP_KEY}|" \
        /var/www/html/.env

else

    echo "APP_KEY=${APP_KEY}" \
        >> /var/www/html/.env

fi


# ==============================================================================
# FIX MODULE PERMISSIONS AGAIN AT RUNTIME
#
# This is intentionally repeated.
#
# It guarantees the PHP-FPM user can read Starter26 even if the filesystem
# permissions change between image build and container startup.
# ==============================================================================

echo "Applying Starter26 permissions..."


chown -R www-data:www-data \
    /var/www/html/modules


find /var/www/html/modules \
    -type d \
    -exec chmod 755 {} \;


find /var/www/html/modules \
    -type f \
    -exec chmod 644 {} \;


# ==============================================================================
# LARAVEL STORAGE PERMISSIONS
# ==============================================================================

echo "Applying Laravel permissions..."


chown -R www-data:www-data \
    /var/www/html/storage \
    /var/www/html/bootstrap/cache


chmod -R 775 \
    /var/www/html/storage \
    /var/www/html/bootstrap/cache


# ==============================================================================
# CLEAR LARAVEL CACHES
# ==============================================================================

echo "Clearing Laravel caches..."


php artisan optimize:clear


# ==============================================================================
# STARTER26 MODULE CHECK
# ==============================================================================

echo ""
echo "=================================================="
echo "STARTER26 MODULE CHECK"
echo "=================================================="


if [ ! -f \
    /var/www/html/modules/Starter26/module.json \
]; then

    echo "ERROR: Starter26 module is missing."

    exit 1

fi


echo "Starter26 module: FOUND"


# ==============================================================================
# STARTER26 PROVIDER CHECK
# ==============================================================================

echo ""
echo "=================================================="
echo "STARTER26 PROVIDER CHECK"
echo "=================================================="


if [ ! -r \
    /var/www/html/modules/Starter26/app/Providers/Starter26ServiceProvider.php
]; then

    echo "ERROR: Starter26ServiceProvider.php is not readable."

    exit 1

fi


if [ ! -r \
    /var/www/html/modules/Starter26/app/Providers/Starter26LivewireServiceProvider.php
]; then

    echo "ERROR: Starter26LivewireServiceProvider.php is not readable."

    exit 1

fi


echo "Starter26 providers: READABLE"


# ==============================================================================
# STARTER26 ASSET CHECK
# ==============================================================================

echo ""
echo "=================================================="
echo "STARTER26 ASSET CHECK"
echo "=================================================="


if [ ! -f \
    /var/www/html/public/build-starter26/manifest.json
]; then

    echo "ERROR: Starter26 Vite manifest is missing."

    exit 1

fi


echo "Starter26 Vite manifest: FOUND"


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

echo "Applying final permissions..."


chown -R www-data:www-data \
    /var/www/html/modules \
    /var/www/html/storage \
    /var/www/html/bootstrap/cache \
    /var/www/html/public/build-starter26


find /var/www/html/modules \
    -type d \
    -exec chmod 755 {} \;


find /var/www/html/modules \
    -type f \
    -exec chmod 644 {} \;


chmod -R 775 \
    /var/www/html/storage \
    /var/www/html/bootstrap/cache


# ==============================================================================
# START APPLICATION
# ==============================================================================

echo ""
echo "=================================================="
echo "Starting Nginx + PHP-FPM"
echo "=================================================="
echo ""


exec /usr/bin/supervisord \
    -c /etc/supervisord.conf

EOF


RUN chmod +x /usr/local/bin/entrypoint.sh


# ==============================================================================
# RENDER PORT
# ==============================================================================

EXPOSE 80


# ==============================================================================
# START
# ==============================================================================

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
```
