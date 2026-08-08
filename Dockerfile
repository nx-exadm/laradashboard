# ==============================================================================
# LARADASHBOARD + STARTER26 + FORUM
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
    curl \
    bash

WORKDIR /app


# ==============================================================================
# COPY APPLICATION
# ==============================================================================

COPY . .


# ==============================================================================
# INSTALL STARTER26 MODULE FROM ZIP
# ==============================================================================

RUN set -eux; \
    echo "=================================================="; \
    echo "INSTALLING STARTER26"; \
    echo "=================================================="; \
    \
    STARTER_ZIP="$(find /app -maxdepth 1 -type f -iname 'starter26-v*.zip' | head -n 1)"; \
    \
    if [ -z "$STARTER_ZIP" ]; then \
        echo "ERROR: Starter26 ZIP not found in repository root."; \
        echo "Expected something like: starter26-v1.0.4.zip"; \
        exit 1; \
    fi; \
    \
    echo "Starter26 ZIP: $STARTER_ZIP"; \
    \
    mkdir -p /app/modules; \
    rm -rf /app/modules/Starter26; \
    mkdir -p /tmp/starter26-install; \
    \
    unzip -q "$STARTER_ZIP" -d /tmp/starter26-install; \
    \
    if [ -f /tmp/starter26-install/Starter26/module.json ]; then \
        mv /tmp/starter26-install/Starter26 /app/modules/Starter26; \
    elif [ -f /tmp/starter26-install/module.json ]; then \
        mkdir -p /app/modules/Starter26; \
        cp -a /tmp/starter26-install/. /app/modules/Starter26/; \
    else \
        echo "ERROR: Starter26 module.json was not found inside ZIP."; \
        find /tmp/starter26-install -maxdepth 5 -type f | sort; \
        exit 1; \
    fi; \
    \
    rm -rf /tmp/starter26-install; \
    \
    test -f /app/modules/Starter26/module.json; \
    echo "Starter26 installed successfully."


# ==============================================================================
# INSTALL FORUM MODULE FROM ZIP
# ==============================================================================

RUN set -eux; \
    echo "=================================================="; \
    echo "INSTALLING FORUM"; \
    echo "=================================================="; \
    \
    FORUM_ZIP="$(find /app -maxdepth 1 -type f -iname 'forum-v*.zip' | head -n 1)"; \
    \
    if [ -z "$FORUM_ZIP" ]; then \
        echo "ERROR: Forum ZIP not found in repository root."; \
        echo "Expected something like: forum-v0.1.3.zip"; \
        exit 1; \
    fi; \
    \
    echo "Forum ZIP: $FORUM_ZIP"; \
    \
    mkdir -p /app/modules; \
    rm -rf /app/modules/Forum; \
    mkdir -p /tmp/forum-install; \
    \
    unzip -q "$FORUM_ZIP" -d /tmp/forum-install; \
    \
    if [ -f /tmp/forum-install/Forum/module.json ]; then \
        mv /tmp/forum-install/Forum /app/modules/Forum; \
    elif [ -f /tmp/forum-install/module.json ]; then \
        mkdir -p /app/modules/Forum; \
        cp -a /tmp/forum-install/. /app/modules/Forum/; \
    else \
        echo "ERROR: Forum module.json was not found inside ZIP."; \
        find /tmp/forum-install -maxdepth 5 -type f | sort; \
        exit 1; \
    fi; \
    \
    rm -rf /tmp/forum-install; \
    \
    test -f /app/modules/Forum/module.json; \
    echo "Forum installed successfully."


# ==============================================================================
# VERIFY MODULES
# ==============================================================================

RUN set -eux; \
    echo ""; \
    echo "=================================================="; \
    echo "STARTER26 MODULE CHECK"; \
    echo "=================================================="; \
    test -f /app/modules/Starter26/module.json; \
    cat /app/modules/Starter26/module.json; \
    \
    echo ""; \
    echo "=================================================="; \
    echo "FORUM MODULE CHECK"; \
    echo "=================================================="; \
    test -f /app/modules/Forum/module.json; \
    cat /app/modules/Forum/module.json; \
    \
    echo ""; \
    echo "=================================================="; \
    echo "FORUM VITE CONFIG"; \
    echo "=================================================="; \
    test -f /app/modules/Forum/vite.config.js; \
    cat /app/modules/Forum/vite.config.js


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
# NODE / NPM
# ==============================================================================

RUN node --version && npm --version


# ==============================================================================
# STARTER26 FRONTEND BUILD
#
# Build Starter26 separately so its manifest is created at:
#
# public/build-starter26/manifest.json
# ==============================================================================

RUN set -eux; \
    echo ""; \
    echo "=================================================="; \
    echo "BUILDING STARTER26 ASSETS"; \
    echo "=================================================="; \
    \
    if [ -f /app/modules/Starter26/package.json ]; then \
        cd /app/modules/Starter26; \
        \
        if [ -f package-lock.json ]; then \
            npm ci; \
        else \
            npm install; \
        fi; \
        \
        npm run build; \
    else \
        echo "ERROR: Starter26 package.json not found."; \
        exit 1; \
    fi; \
    \
    test -f /app/public/build-starter26/manifest.json; \
    \
    echo ""; \
    echo "Starter26 Vite manifest:"; \
    cat /app/public/build-starter26/manifest.json


# ==============================================================================
# FORUM FRONTEND BUILD
#
# The Forum vite.config.js is designed to build to:
#
# public/build-forum/
#
# This creates:
#
# public/build-forum/manifest.json
# ==============================================================================

RUN set -eux; \
    echo ""; \
    echo "=================================================="; \
    echo "BUILDING FORUM ASSETS"; \
    echo "=================================================="; \
    \
    cd /app/modules/Forum; \
    \
    if [ -f package-lock.json ]; then \
        npm ci; \
    else \
        npm install; \
    fi; \
    \
    npm run build; \
    \
    test -f /app/public/build-forum/manifest.json; \
    \
    echo ""; \
    echo "Forum Vite manifest:"; \
    cat /app/public/build-forum/manifest.json


# ==============================================================================
# VERIFY BOTH VITE BUILDS
# ==============================================================================

RUN set -eux; \
    echo ""; \
    echo "=================================================="; \
    echo "FINAL VITE BUILD CHECK"; \
    echo "=================================================="; \
    \
    test -f /app/public/build-starter26/manifest.json; \
    test -f /app/public/build-forum/manifest.json; \
    \
    echo "Starter26 manifest: FOUND"; \
    echo "Forum manifest: FOUND"; \
    \
    echo ""; \
    echo "Starter26 build files:"; \
    find /app/public/build-starter26 -maxdepth 3 -type f | sort; \
    \
    echo ""; \
    echo "Forum build files:"; \
    find /app/public/build-forum -maxdepth 3 -type f | sort


# ==============================================================================
# STAGE 2: PRODUCTION
# ==============================================================================

FROM php:8.3-fpm-alpine


# ==============================================================================
# RUNTIME PACKAGES
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
    /var/www/html/bootstrap/cache


# ==============================================================================
# FILE PERMISSIONS
# ==============================================================================

RUN chown -R www-data:www-data /var/www/html \
    && find /var/www/html -type d -exec chmod 755 {} \; \
    && find /var/www/html -type f -exec chmod 644 {} \; \
    && chmod -R 775 /var/www/html/storage \
    && chmod -R 775 /var/www/html/bootstrap/cache \
    && chmod +x /var/www/html/artisan


# ==============================================================================
# FINAL MODULE VERIFICATION
# ==============================================================================

RUN set -eux; \
    echo "=================================================="; \
    echo "FINAL MODULE VERIFICATION"; \
    echo "=================================================="; \
    \
    test -f /var/www/html/modules/Starter26/module.json; \
    test -f /var/www/html/modules/Forum/module.json; \
    \
    echo "Starter26: FOUND"; \
    echo "Forum: FOUND"; \
    \
    echo ""; \
    echo "Providers:"; \
    \
    test -f /var/www/html/modules/Starter26/app/Providers/Starter26ServiceProvider.php; \
    test -f /var/www/html/modules/Forum/app/Providers/ForumServiceProvider.php; \
    \
    echo "Starter26 provider: FOUND"; \
    echo "Forum provider: FOUND"; \
    \
    echo ""; \
    echo "Vite manifests:"; \
    \
    test -f /var/www/html/public/build-starter26/manifest.json; \
    test -f /var/www/html/public/build-forum/manifest.json; \
    \
    echo "Starter26 manifest: FOUND"; \
    echo "Forum manifest: FOUND"


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


# ==============================================================================
# FORUM CHECK
# ==============================================================================

echo ""
echo "=================================================="
echo "FORUM CHECK"
echo "=================================================="

if [ ! -f /var/www/html/modules/Forum/module.json ]; then
    echo "ERROR: Forum module is missing."
    exit 1
fi

echo "Forum module: FOUND"


# ==============================================================================
# VITE CHECK
# ==============================================================================

echo ""
echo "=================================================="
echo "VITE ASSET CHECK"
echo "=================================================="

if [ ! -f /var/www/html/public/build-starter26/manifest.json ]; then
    echo "ERROR: Starter26 Vite manifest is missing."
    exit 1
fi

if [ ! -f /var/www/html/public/build-forum/manifest.json ]; then
    echo "ERROR: Forum Vite manifest is missing."
    exit 1
fi

echo "Starter26 Vite manifest: FOUND"
echo "Forum Vite manifest: FOUND"


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
# FORUM ROUTES
# ==============================================================================

echo ""
echo "=================================================="
echo "FORUM ROUTES"
echo "=================================================="

php artisan route:list 2>/dev/null | grep -i forum || true


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
# FINAL STATUS
# ==============================================================================

echo ""
echo "=================================================="
echo "LARADASHBOARD READY"
echo "=================================================="
echo "Starter26: ENABLED"
echo "Forum: ENABLED"
echo "Starter26 Vite: READY"
echo "Forum Vite: READY"
echo "=================================================="
echo ""


# ==============================================================================
# START
# ==============================================================================

exec /usr/bin/supervisord -c /etc/supervisord.conf
EOF

RUN chmod +x /usr/local/bin/entrypoint.sh


# ==============================================================================
# RENDER
# ==============================================================================

EXPOSE 80

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
