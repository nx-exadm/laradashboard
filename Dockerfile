```dockerfile
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
    curl

WORKDIR /app

# ------------------------------------------------------------------------------
# Copy application
# ------------------------------------------------------------------------------

COPY . .

# ==============================================================================
# INSTALL STARTER26 MODULE
# ==============================================================================

RUN set -eux; \
    echo ""; \
    echo "=================================================="; \
    echo "INSTALLING STARTER26"; \
    echo "=================================================="; \
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
        find /tmp/starter26-install -maxdepth 4 -type f | sort; \
        exit 1; \
    fi; \
    rm -rf /tmp/starter26-install; \
    rm -f /app/starter26-v1.0.4.zip; \
    test -f /app/modules/Starter26/module.json; \
    echo ""; \
    echo "STARTER26 INSTALLED SUCCESSFULLY"; \
    cat /app/modules/Starter26/module.json

# ==============================================================================
# INSTALL FORUM MODULE
# ==============================================================================

RUN set -eux; \
    echo ""; \
    echo "=================================================="; \
    echo "INSTALLING FORUM"; \
    echo "=================================================="; \
    test -f /app/forum-v0.1.3.zip; \
    mkdir -p /app/modules; \
    rm -rf /app/modules/Forum; \
    mkdir -p /tmp/forum-install; \
    unzip -q /app/forum-v0.1.3.zip -d /tmp/forum-install; \
    if [ -f /tmp/forum-install/Forum/module.json ]; then \
        mv /tmp/forum-install/Forum /app/modules/Forum; \
    elif [ -f /tmp/forum-install/module.json ]; then \
        mv /tmp/forum-install /app/modules/Forum; \
    else \
        echo "ERROR: Forum module.json was not found inside ZIP"; \
        find /tmp/forum-install -maxdepth 5 -type f | sort; \
        exit 1; \
    fi; \
    rm -rf /tmp/forum-install; \
    rm -f /app/forum-v0.1.3.zip; \
    test -f /app/modules/Forum/module.json; \
    echo ""; \
    echo "FORUM INSTALLED SUCCESSFULLY"; \
    cat /app/modules/Forum/module.json

# ==============================================================================
# VERIFY BOTH MODULES
# ==============================================================================

RUN set -eux; \
    echo ""; \
    echo "=================================================="; \
    echo "VERIFYING MODULES"; \
    echo "=================================================="; \
    test -f /app/modules/Starter26/module.json; \
    test -f /app/modules/Starter26/app/Providers/Starter26ServiceProvider.php; \
    test -f /app/modules/Forum/module.json; \
    test -f /app/modules/Forum/app/Providers/ForumServiceProvider.php; \
    test -f /app/modules/Forum/app/Providers/LivewireServiceProvider.php; \
    test -f /app/modules/Forum/app/Providers/RouteServiceProvider.php; \
    echo ""; \
    echo "STARTER26 FILES:"; \
    find /app/modules/Starter26 -maxdepth 3 -type f | sort; \
    echo ""; \
    echo "FORUM FILES:"; \
    find /app/modules/Forum -maxdepth 3 -type f | sort

# ==============================================================================
# PREPARE FORUM PRODUCTION ASSETS
# ==============================================================================

RUN set -eux; \
    echo ""; \
    echo "=================================================="; \
    echo "PREPARING FORUM VITE ASSETS"; \
    echo "=================================================="; \
    test -f /app/modules/Forum/dist/build-forum/manifest.json; \
    mkdir -p /app/public/build-forum; \
    rm -rf /app/public/build-forum/*; \
    cp -R /app/modules/Forum/dist/build-forum/. /app/public/build-forum/; \
    echo ""; \
    echo "FORUM VITE MANIFEST:"; \
    cat /app/public/build-forum/manifest.json; \
    echo ""; \
    echo "FORUM VITE ASSETS:"; \
    find /app/public/build-forum -maxdepth 3 -type f | sort

# ==============================================================================
# PREPARE FORUM LOGO
# ==============================================================================

RUN set -eux; \
    echo ""; \
    echo "=================================================="; \
    echo "PREPARING FORUM LOGO"; \
    echo "=================================================="; \
    test -f /app/modules/Forum/marketplace-assets/logo.svg; \
    mkdir -p /app/public/images/modules/forum; \
    cp /app/modules/Forum/marketplace-assets/logo.svg \
       /app/public/images/modules/forum/logo.svg; \
    test -f /app/public/images/modules/forum/logo.svg; \
    echo "Forum logo installed."

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
# FRONTEND
# ==============================================================================

RUN npm ci

RUN npm run build

# ==============================================================================
# FINAL VITE VERIFICATION
# ==============================================================================

RUN set -eux; \
    echo ""; \
    echo "=================================================="; \
    echo "FINAL VITE VERIFICATION"; \
    echo "=================================================="; \
    echo ""; \
    echo "Starter26 build:"; \
    test -f /app/public/build-starter26/manifest.json; \
    cat /app/public/build-starter26/manifest.json; \
    echo ""; \
    echo "Forum build:"; \
    test -f /app/public/build-forum/manifest.json; \
    cat /app/public/build-forum/manifest.json; \
    echo ""; \
    echo "Both Vite manifests exist."

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
# LARAVEL DIRECTORIES
# ==============================================================================

RUN mkdir -p \
    /var/www/html/storage/app/public \
    /var/www/html/storage/framework/cache \
    /var/www/html/storage/framework/sessions \
    /var/www/html/storage/framework/views \
    /var/www/html/storage/logs \
    /var/www/html/bootstrap/cache \
    /var/www/html/public/build-starter26 \
    /var/www/html/public/build-forum \
    /var/www/html/public/images/modules/forum

# ==============================================================================
# FIX FILE OWNERSHIP / PERMISSIONS
# ==============================================================================

RUN chown -R www-data:www-data /var/www/html \
    && find /var/www/html -type d -exec chmod 755 {} \; \
    && find /var/www/html -type f -exec chmod 644 {} \; \
    && chmod -R 775 /var/www/html/storage \
    && chmod -R 775 /var/www/html/bootstrap/cache \
    && chmod +x /var/www/html/artisan

# ==============================================================================
# VERIFY STARTER26
# ==============================================================================

RUN set -eux; \
    echo ""; \
    echo "=================================================="; \
    echo "FINAL STARTER26 CHECK"; \
    echo "=================================================="; \
    test -f /var/www/html/modules/Starter26/module.json; \
    test -f /var/www/html/modules/Starter26/app/Providers/Starter26ServiceProvider.php; \
    test -f /var/www/html/modules/Starter26/app/Providers/Starter26LivewireServiceProvider.php; \
    test -f /var/www/html/public/build-starter26/manifest.json; \
    echo "Starter26 module: FOUND"; \
    echo "Starter26 Vite manifest: FOUND"

# ==============================================================================
# VERIFY FORUM
# ==============================================================================

RUN set -eux; \
    echo ""; \
    echo "=================================================="; \
    echo "FINAL FORUM CHECK"; \
    echo "=================================================="; \
    test -f /var/www/html/modules/Forum/module.json; \
    test -f /var/www/html/modules/Forum/app/Providers/ForumServiceProvider.php; \
    test -f /var/www/html/modules/Forum/app/Providers/LivewireServiceProvider.php; \
    test -f /var/www/html/modules/Forum/app/Providers/RouteServiceProvider.php; \
    test -f /var/www/html/modules/Forum/database/migrations/2026_02_14_182041_create_forum_categories_table.php; \
    test -f /var/www/html/modules/Forum/database/migrations/2026_02_14_182047_create_forum_topics_table.php; \
    test -f /var/www/html/modules/Forum/database/migrations/2026_02_14_182051_create_forum_replies_table.php; \
    test -f /var/www/html/modules/Forum/database/migrations/2026_02_14_182104_create_forum_likes_table.php; \
    test -f /var/www/html/public/build-forum/manifest.json; \
    test -f /var/www/html/public/images/modules/forum/logo.svg; \
    echo "Forum module: FOUND"; \
    echo "Forum migrations: FOUND"; \
    echo "Forum Vite manifest: FOUND"; \
    echo "Forum logo: FOUND"

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

echo ""
echo "Applying Laravel permissions..."

chown -R www-data:www-data \
    /var/www/html/storage \
    /var/www/html/bootstrap/cache

find /var/www/html/modules -type d -exec chmod 755 {} \;
find /var/www/html/modules -type f -exec chmod 644 {} \;

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

if [ ! -f /var/www/html/public/build-starter26/manifest.json ]; then
    echo "ERROR: Starter26 Vite manifest is missing."
    exit 1
fi

echo "Starter26 module: FOUND"
echo "Starter26 Vite manifest: FOUND"

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

if [ ! -f /var/www/html/public/build-forum/manifest.json ]; then
    echo "ERROR: Forum Vite manifest is missing."
    exit 1
fi

if [ ! -f /var/www/html/public/images/modules/forum/logo.svg ]; then
    echo "ERROR: Forum logo is missing."
    exit 1
fi

echo "Forum module: FOUND"
echo "Forum Vite manifest: FOUND"
echo "Forum logo: FOUND"

echo ""
echo "Forum providers:"
ls -la /var/www/html/modules/Forum/app/Providers

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
# RUN DATABASE MIGRATIONS
# ==============================================================================

echo ""
echo "=================================================="
echo "RUNNING DATABASE MIGRATIONS"
echo "=================================================="

php artisan migrate --force

# ==============================================================================
# FORUM ROUTES
# ==============================================================================

echo ""
echo "=================================================="
echo "FORUM ROUTES"
echo "=================================================="

php artisan route:list 2>/dev/null | grep -E 'forum|admin.forum' || true

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
# FINAL ASSET CHECK
# ==============================================================================

echo ""
echo "=================================================="
echo "FINAL ASSET CHECK"
echo "=================================================="

echo "Starter26 manifest:"
ls -lh /var/www/html/public/build-starter26/manifest.json

echo ""
echo "Forum manifest:"
ls -lh /var/www/html/public/build-forum/manifest.json

echo ""
echo "Forum logo:"
ls -lh /var/www/html/public/images/modules/forum/logo.svg

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
```
