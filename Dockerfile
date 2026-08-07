# ==============================================================================
# LARADASHBOARD + STARTER26
# Production Docker image for Render
# ==============================================================================


# ==============================================================================
# STAGE 1 — BUILD
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


# ==============================================================================
# COPY APPLICATION
# ==============================================================================

COPY . .


# ==============================================================================
# INSTALL REAL STARTER26 ZIP
# ==============================================================================

RUN echo "==================================================" \
    && echo "Installing Starter26" \
    && echo "==================================================" \
    && test -f /app/starter26-v1.0.4.zip \
    && mkdir -p /app/modules \
    && rm -rf /app/modules/Starter26 \
    && rm -rf /tmp/starter26-install \
    && mkdir -p /tmp/starter26-install \
    && unzip -q /app/starter26-v1.0.4.zip -d /tmp/starter26-install \
    && if [ -f /tmp/starter26-install/Starter26/module.json ]; then \
         mv /tmp/starter26-install/Starter26 /app/modules/Starter26; \
       elif [ -f /tmp/starter26-install/module.json ]; then \
         mv /tmp/starter26-install /app/modules/Starter26; \
       else \
         echo "ERROR: Could not find Starter26/module.json inside ZIP"; \
         find /tmp/starter26-install -maxdepth 3 -type f | sort; \
         exit 1; \
       fi \
    && rm -rf /tmp/starter26-install \
    && echo "Starter26 installed successfully."


# ==============================================================================
# VERIFY STARTER26
# ==============================================================================

RUN echo "==================================================" \
    && echo "STARTER26 DIRECTORY" \
    && echo "==================================================" \
    && find /app/modules/Starter26 -maxdepth 3 -type f | sort


RUN echo "==================================================" \
    && echo "STARTER26 MANIFEST" \
    && echo "==================================================" \
    && test -f /app/modules/Starter26/module.json \
    && cat /app/modules/Starter26/module.json


# ==============================================================================
# COMPOSER
# ==============================================================================

COPY --from=composer:2.7 /usr/bin/composer /usr/local/bin/composer


RUN composer install \
    --no-interaction \
    --prefer-dist \
    --optimize-autoloader \
    --ignore-platform-reqs


# ------------------------------------------------------------------------------
# Rebuild autoload
# ------------------------------------------------------------------------------

RUN composer dump-autoload \
    --optimize \
    --no-interaction


# ==============================================================================
# FRONTEND
# ==============================================================================

RUN npm ci

RUN npm run build


# ==============================================================================
# STAGE 2 — PRODUCTION
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
    mariadb-client \
    unzip


# ==============================================================================
# PHP EXTENSIONS
# ==============================================================================

COPY --from=mlocati/php-extension-installer \
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
# VERIFY FINAL STARTER26
# ==============================================================================

RUN echo "==================================================" \
    && echo "FINAL IMAGE — STARTER26" \
    && echo "==================================================" \
    && test -f /var/www/html/modules/Starter26/module.json \
    && cat /var/www/html/modules/Starter26/module.json


RUN echo "==================================================" \
    && echo "STARTER26 ASSETS" \
    && echo "==================================================" \
    && if [ -d /var/www/html/modules/Starter26/dist ]; then \
         find /var/www/html/modules/Starter26/dist -type f | sort; \
       else \
         echo "WARNING: Starter26 dist directory not found"; \
       fi


# ==============================================================================
# LARAVEL DIRECTORIES
# ==============================================================================

RUN mkdir -p \
    /var/www/html/storage/app/public \
    /var/www/html/storage/framework/cache \
    /var/www/html/storage/framework/sessions \
    /var/www/html/storage/framework/views \
    /var/www/html/storage/logs \
    /var/www/html/bootstrap/cache


# ==============================================================================
# NGINX
#
# IMPORTANT:
# Render supplies PORT.
# Default Render PORT = 10000.
#
# We generate the config at container startup so Nginx listens on
# the actual Render PORT.
# ==============================================================================


RUN mkdir -p /etc/nginx/http.d


RUN cat <<'EOF' > /usr/local/bin/configure-nginx.sh
#!/bin/sh

set -e

PORT="${PORT:-10000}"

echo "Configuring Nginx on port ${PORT}..."

cat > /etc/nginx/http.d/default.conf <<NGINX
server {
    listen 0.0.0.0:${PORT} default_server;
    server_name _;

    root /var/www/html/public;

    index index.php index.html;

    charset utf-8;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        try_files \$uri =404;

        fastcgi_pass 127.0.0.1:9000;

        fastcgi_index index.php;

        include fastcgi_params;

        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param DOCUMENT_ROOT \$document_root;
    }

    location ~ /\.ht {
        deny all;
    }
}
NGINX

EOF


RUN chmod +x /usr/local/bin/configure-nginx.sh


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
echo ""



# ==============================================================================
# RENDER PORT
# ==============================================================================

export PORT="${PORT:-10000}"

echo "HTTP PORT: ${PORT}"


# ==============================================================================
# APP KEY
# ==============================================================================

if [ -z "${APP_KEY:-}" ]; then

    echo ""
    echo "ERROR: APP_KEY is missing."
    echo ""
    echo "Add APP_KEY to Render Environment Variables."
    echo ""

    exit 1

fi

echo "APP_KEY detected."


# ==============================================================================
# CREATE .ENV
# ==============================================================================

if [ ! -f /var/www/html/.env ]; then

    if [ -f /var/www/html/.env.example ]; then
        cp /var/www/html/.env.example /var/www/html/.env
    else
        touch /var/www/html/.env
    fi

fi


# ==============================================================================
# SET APP_KEY
# ==============================================================================

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

chmod -R 775 \
    /var/www/html/storage \
    /var/www/html/bootstrap/cache


# ==============================================================================
# CONFIGURE NGINX
# ==============================================================================

echo "Configuring Nginx..."

/usr/local/bin/configure-nginx.sh


# ==============================================================================
# CLEAR OLD LARAVEL CACHE
# ==============================================================================

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
# STARTER26 CHECK
# ==============================================================================

echo ""
echo "=================================================="
echo "STARTER26 CHECK"
echo "=================================================="

if [ -f /var/www/html/modules/Starter26/module.json ]; then

    echo "Starter26 module: FOUND"

    echo ""
    echo "Starter26 manifest:"
    cat /var/www/html/modules/Starter26/module.json

else

    echo ""
    echo "ERROR: Starter26 module is missing."
    echo ""

    exit 1

fi


# ==============================================================================
# ROUTE CHECK
# ==============================================================================

echo ""
echo "=================================================="
echo "CURRENT ROUTES"
echo "=================================================="

php artisan route:list --except-vendor 2>/dev/null || php artisan route:list || true


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

chown -R www-data:www-data \
    /var/www/html/storage \
    /var/www/html/bootstrap/cache

chmod -R 775 \
    /var/www/html/storage \
    /var/www/html/bootstrap/cache


# ==============================================================================
# NGINX TEST
# ==============================================================================

echo ""
echo "Testing Nginx configuration..."

nginx -t


# ==============================================================================
# START
# ==============================================================================

echo ""
echo "=================================================="
echo "Starting LaraDashboard"
echo "Nginx: 0.0.0.0:${PORT}"
echo "PHP-FPM: 127.0.0.1:9000"
echo "=================================================="
echo ""

exec /usr/bin/supervisord -c /etc/supervisord.conf

EOF


RUN chmod +x /usr/local/bin/entrypoint.sh


# ==============================================================================
# RENDER
# ==============================================================================

EXPOSE 10000

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
