# ==============================================================================
# LARADASHBOARD + STARTER26
# Production Docker image for Render
# ==============================================================================

# ==============================================================================
# STAGE 1: BUILD
# ==============================================================================

FROM php:8.3-fpm-alpine AS builder

# ------------------------------------------------------------------------------
# Build dependencies
# ------------------------------------------------------------------------------

RUN apk add --no-cache \
    nodejs \
    npm \
    zip \
    unzip \
    libzip-dev \
    git \
    curl

WORKDIR /app

# ------------------------------------------------------------------------------
# Copy application
# ------------------------------------------------------------------------------

COPY . .

# ------------------------------------------------------------------------------
# Install Starter26 from the ZIP committed to the repository
#
# Expected:
# starter26-v1.0.4.zip
#
# ZIP structure:
# Starter26/
#   app/
#   config/
#   database/
#   dist/
#   resources/
#   routes/
#   module.json
# ------------------------------------------------------------------------------

RUN set -eux; \
    test -f /app/starter26-v1.0.4.zip; \
    mkdir -p /app/modules; \
    rm -rf /app/modules/Starter26; \
    mkdir -p /tmp/starter26-install; \
    unzip -q /app/starter26-v1.0.4.zip -d /tmp/starter26-install; \
    if [ -f /tmp/starter26-install/Starter26/module.json ]; then \
        mv /tmp/starter26-install/Starter26 /app/modules/Starter26; \
    elif [ -f /tmp/starter26-install/module.json ]; then \
        mv /tmp/starter26-install /app/modules/Starter26; \
    else \
        echo "ERROR: Starter26 module.json was not found inside ZIP"; \
        find /tmp/starter26-install -maxdepth 5 -type f | sort; \
        exit 1; \
    fi; \
    rm -f /app/starter26-v1.0.4.zip

# ------------------------------------------------------------------------------
# Verify Starter26
# ------------------------------------------------------------------------------

RUN set -eux; \
    test -f /app/modules/Starter26/module.json; \
    test -f /app/modules/Starter26/app/Providers/Starter26ServiceProvider.php; \
    test -f /app/modules/Starter26/app/Providers/Starter26LivewireServiceProvider.php; \
    test -f /app/modules/Starter26/dist/build-starter26/manifest.json; \
    echo "=================================================="; \
    echo "STARTER26 MODULE FOUND"; \
    echo "=================================================="; \
    cat /app/modules/Starter26/module.json; \
    echo "=================================================="; \
    echo "STARTER26 PRODUCTION VITE MANIFEST FOUND"; \
    echo "=================================================="; \
    cat /app/modules/Starter26/dist/build-starter26/manifest.json

# ------------------------------------------------------------------------------
# IMPORTANT:
# The Starter26 ZIP already contains its compiled production Vite assets.
#
# Laravel expects:
# public/build-starter26/manifest.json
#
# The ZIP contains:
# modules/Starter26/dist/build-starter26/manifest.json
#
# Copy the packaged production build into Laravel's public directory.
# ------------------------------------------------------------------------------

RUN set -eux; \
    mkdir -p /app/public/build-starter26; \
    cp -R /app/modules/Starter26/dist/build-starter26/. /app/public/build-starter26/; \
    test -f /app/public/build-starter26/manifest.json; \
    echo "=================================================="; \
    echo "PUBLIC STARTER26 VITE BUILD"; \
    echo "=================================================="; \
    find /app/public/build-starter26 -maxdepth 2 -type f | sort

# ==============================================================================
# COMPOSER
# ==============================================================================

COPY --from=composer:2.7 /usr/bin/composer /usr/local/bin/composer

RUN composer install \
    --no-interaction \
    --prefer-dist \
    --optimize-autoloader \
    --ignore-platform-reqs

RUN composer dump-autoload \
    --optimize \
    --no-interaction

# ==============================================================================
# NOTE
#
# Do NOT run "npm run build" here.
#
# Starter26 v1.0.4 already contains:
#
# modules/Starter26/dist/build-starter26/manifest.json
#
# and its compiled CSS/JS files.
#
# We copied those files into:
#
# public/build-starter26/
#
# which is exactly where Laravel @vite(..., 'build-starter26')
# expects them.
# ==============================================================================


# ==============================================================================
# STAGE 2: PRODUCTION
# ==============================================================================

FROM php:8.3-fpm-alpine

# ------------------------------------------------------------------------------
# Runtime packages
# ------------------------------------------------------------------------------

RUN apk add --no-cache \
    nginx \
    supervisor \
    bash \
    postgresql-client \
    mariadb-client \
    unzip

# ==============================================================================
# PHP EXTENSIONS
# ==============================================================================

COPY --from=mlocati/php-extension-installer:latest \
    /usr/bin/install-php-extensions \
    /usr/local/bin/install-php-extensions

RUN chmod +x /usr/local/bin/install-php-extensions \
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
# PHP CONFIGURATION
# ==============================================================================

RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

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
# LARAVEL DIRECTORIES
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
# FILE OWNERSHIP / PERMISSIONS
# ==============================================================================

RUN chown -R www-data:www-data /var/www/html \
    && find /var/www/html -type d -exec chmod 755 {} \; \
    && find /var/www/html -type f -exec chmod 644 {} \; \
    && chmod -R 775 /var/www/html/storage \
    && chmod -R 775 /var/www/html/bootstrap/cache \
    && chmod +x /var/www/html/artisan

# ------------------------------------------------------------------------------
# Verify Starter26 after copy and permissions
# ------------------------------------------------------------------------------

RUN set -eux; \
    test -f /var/www/html/modules/Starter26/module.json; \
    test -f /var/www/html/modules/Starter26/app/Providers/Starter26ServiceProvider.php; \
    test -f /var/www/html/modules/Starter26/app/Providers/Starter26LivewireServiceProvider.php; \
    test -f /var/www/html/modules/Starter26/dist/build-starter26/manifest.json; \
    test -f /var/www/html/public/build-starter26/manifest.json; \
    echo "=================================================="; \
    echo "FINAL STARTER26 CHECK"; \
    echo "=================================================="; \
    ls -la /var/www/html/modules/Starter26; \
    echo "--------------------------------------------------"; \
    echo "Starter26 providers:"; \
    ls -la /var/www/html/modules/Starter26/app/Providers; \
    echo "--------------------------------------------------"; \
    echo "Public Vite build:"; \
    ls -la /var/www/html/public/build-starter26; \
    echo "--------------------------------------------------"; \
    echo "Vite manifest:"; \
    cat /var/www/html/public/build-starter26/manifest.json

# ==============================================================================
# NGINX
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
echo "LaraDashboard Production Startup"
echo "=================================================="

# ==============================================================================
# RENDER PORT
# ==============================================================================

PORT="${PORT:-80}"

echo "HTTP PORT: ${PORT}"

sed -i "s/listen 80 default_server;/listen ${PORT} default_server;/" \
    /etc/nginx/http.d/default.conf

# ==============================================================================
# APP KEY
# ==============================================================================

if [ -z "${APP_KEY:-}" ]; then
    echo ""
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
# PERMISSIONS
# ==============================================================================

echo "Applying Laravel permissions..."

chown -R www-data:www-data \
    /var/www/html/storage \
    /var/www/html/bootstrap/cache

find /var/www/html/modules -type d -exec chmod 755 {} \;
find /var/www/html/modules -type f -exec chmod 644 {} \;

find /var/www/html/app -type d -exec chmod 755 {} \; 2>/dev/null || true
find /var/www/html/app -type f -exec chmod 644 {} \; 2>/dev/null || true

find /var/www/html/public/build-starter26 -type d -exec chmod 755 {} \;
find /var/www/html/public/build-starter26 -type f -exec chmod 644 {} \;

chmod -R 775 /var/www/html/storage
chmod -R 775 /var/www/html/bootstrap/cache

chmod +x /var/www/html/artisan

# ==============================================================================
# STARTER26 CHECK
# ==============================================================================

echo ""
echo "=================================================="
echo "STARTER26 CHECK"
echo "=================================================="

if [ ! -f /var/www/html/modules/Starter26/module.json ]; then
    echo "ERROR: Starter26 module is missing."
    exit 1
fi

echo "Starter26 module: FOUND"

if [ ! -f /var/www/html/modules/Starter26/app/Providers/Starter26ServiceProvider.php ]; then
    echo "ERROR: Starter26ServiceProvider.php is missing."
    exit 1
fi

if [ ! -f /var/www/html/modules/Starter26/app/Providers/Starter26LivewireServiceProvider.php ]; then
    echo "ERROR: Starter26LivewireServiceProvider.php is missing."
    exit 1
fi

echo "Starter26 providers: FOUND"

# ==============================================================================
# STARTER26 VITE CHECK
# ==============================================================================

echo ""
echo "=================================================="
echo "STARTER26 VITE ASSETS"
echo "=================================================="

if [ ! -f /var/www/html/public/build-starter26/manifest.json ]; then
    echo "ERROR: Starter26 Vite manifest is missing."
    echo "Expected:"
    echo "/var/www/html/public/build-starter26/manifest.json"
    exit 1
fi

echo "Starter26 Vite manifest: FOUND"

echo ""
echo "Starter26 Vite files:"
find /var/www/html/public/build-starter26 -maxdepth 2 -type f | sort

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
# STARTER26 ROUTES
# ==============================================================================

echo ""
echo "=================================================="
echo "STARTER26 ROUTES"
echo "=================================================="

php artisan route:list 2>/dev/null | grep -i starter26 || true

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
# STORAGE
# ==============================================================================

echo ""
echo "Creating storage link..."

php artisan storage:link --force || true

# ==============================================================================
# FINAL PERMISSIONS
# ==============================================================================

chown -R www-data:www-data \
    /var/www/html/storage \
    /var/www/html/bootstrap/cache

chmod -R 775 \
    /var/www/html/storage \
    /var/www/html/bootstrap/cache

# ==============================================================================
# FINAL VITE CHECK
# ==============================================================================

echo ""
echo "=================================================="
echo "FINAL VITE CHECK"
echo "=================================================="

test -f /var/www/html/public/build-starter26/manifest.json

echo "Starter26 manifest:"
cat /var/www/html/public/build-starter26/manifest.json

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
