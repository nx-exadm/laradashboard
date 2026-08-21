# ==============================================================================
# LARADASHBOARD + STARTER26 + FORUM + CUSTOMFORM
# Production Docker image for Render
# ==============================================================================

FROM php:8.3-fpm-alpine AS builder

# ==============================================================================
# BUILD DEPENDENCIES
# ==============================================================================

RUN apk add --no-cache nodejs npm zip unzip git curl

WORKDIR /app

# ==============================================================================
# COPY APPLICATION
# ==============================================================================

COPY . .

# ==============================================================================
# INSTALL STARTER26 MODULE
# ==============================================================================

RUN test -f /app/starter26-v1.0.4.zip && mkdir -p /app/modules && rm -rf /app/modules/Starter26 /app/modules/starter26 /tmp/starter26-install && mkdir -p /tmp/starter26-install && unzip -q /app/starter26-v1.0.4.zip -d /tmp/starter26-install && if [ -f /tmp/starter26-install/Starter26/module.json ]; then mv /tmp/starter26-install/Starter26 /app/modules/Starter26; elif [ -f /tmp/starter26-install/module.json ]; then mv /tmp/starter26-install /app/modules/Starter26; else echo "ERROR: Starter26 module.json not found"; find /tmp/starter26-install -maxdepth 4 -type f | sort; exit 1; fi && rm -rf /tmp/starter26-install /app/starter26-v1.0.4.zip && ln -s Starter26 /app/modules/starter26

# ==============================================================================
# INSTALL FORUM MODULE
# ==============================================================================

RUN test -f /app/forum-v0.1.3.zip && mkdir -p /app/modules && rm -rf /app/modules/Forum /app/modules/forum /tmp/forum-install && mkdir -p /tmp/forum-install && unzip -q /app/forum-v0.1.3.zip -d /tmp/forum-install && if [ -f /tmp/forum-install/Forum/module.json ]; then mv /tmp/forum-install/Forum /app/modules/Forum; elif [ -f /tmp/forum-install/module.json ]; then mv /tmp/forum-install /app/modules/Forum; else echo "ERROR: Forum module.json not found"; find /tmp/forum-install -maxdepth 4 -type f | sort; exit 1; fi && rm -rf /tmp/forum-install /app/forum-v0.1.3.zip && ln -s Forum /app/modules/forum

# ==============================================================================
# INSTALL CUSTOMFORM MODULE
#
# NOTE: this module ships with precompiled Vite assets
# (.module-manifest.json: has_precompiled_assets=true, requires_npm_build=false)
# and its own bundled vendor/autoload.php (self-contained module, loaded by
# CustomFormServiceProvider::register()). It is intentionally NOT built with
# npm/vite below -- see the CUSTOMFORM ASSETS step further down.
# ==============================================================================

RUN test -f /app/customform-v1.0.4.zip && mkdir -p /app/modules && rm -rf /app/modules/CustomForm /app/modules/customform /tmp/customform-install && mkdir -p /tmp/customform-install && unzip -q /app/customform-v1.0.4.zip -d /tmp/customform-install && if [ -f /tmp/customform-install/CustomForm/module.json ]; then mv /tmp/customform-install/CustomForm /app/modules/CustomForm; elif [ -f /tmp/customform-install/module.json ]; then mv /tmp/customform-install /app/modules/CustomForm; else echo "ERROR: CustomForm module.json not found"; find /tmp/customform-install -maxdepth 4 -type f | sort; exit 1; fi && rm -rf /tmp/customform-install /app/customform-v1.0.4.zip && ln -s CustomForm /app/modules/customform

# ==============================================================================
# VERIFY MODULES
# ==============================================================================

RUN test -f /app/modules/Starter26/module.json && test -f /app/modules/Forum/module.json && test -f /app/modules/CustomForm/module.json && echo "===== STARTER26 =====" && cat /app/modules/Starter26/module.json && echo "===== FORUM =====" && cat /app/modules/Forum/module.json && echo "===== CUSTOMFORM =====" && cat /app/modules/CustomForm/module.json

# ==============================================================================
# COMPOSER
#
# Module composer.json files (including CustomForm's) are merged into the
# root autoloader here, so modules must already be extracted into /app/modules
# before this step runs -- they are (see steps above).
#
# --no-dev is REQUIRED here. Without it, every package under require-dev in
# composer.json (laravel/boost, larastan, laravel/pint, laravel/sail,
# brianium/paratest, etc.) ships into the production image. laravel/boost in
# particular registers an InjectBoost middleware that injects a browser-side
# logging script into every HTTP response and POSTs console output back to
# /_boost/browser-logs -- meant strictly for local development with AI coding
# tools, never for production. Confirmed this was happening in production
# before this fix was added.
# ==============================================================================

COPY --from=composer:2.7 /usr/bin/composer /usr/local/bin/composer

RUN composer install --no-interaction --prefer-dist --optimize-autoloader --ignore-platform-reqs --no-dev

RUN composer dump-autoload --optimize --no-interaction

# ==============================================================================
# NODE DEPENDENCIES - STARTER26
# ==============================================================================

RUN cd /app/modules/Starter26 && if [ -f package-lock.json ]; then npm ci; else npm install; fi

# ==============================================================================
# NODE DEPENDENCIES - FORUM
# ==============================================================================

RUN cd /app/modules/Forum && if [ -f package-lock.json ]; then npm ci; else npm install; fi

# ==============================================================================
# BUILD STARTER26
#
# IMPORTANT:
# Starter26's vite.config.js expects the application root to be /app.
# Therefore we execute Vite from /app and explicitly point it to the module
# config file.
# ==============================================================================

RUN cd /app && MODULE_DIST_BUILD=true /app/modules/Starter26/node_modules/.bin/vite build --config /app/modules/Starter26/vite.config.js

# ==============================================================================
# BUILD FORUM
#
# Forum has absolute asset paths in its Vite configuration, so we can also
# execute it from /app.
# ==============================================================================

RUN cd /app && MODULE_DIST_BUILD=true /app/modules/Forum/node_modules/.bin/vite build --config /app/modules/Forum/vite.config.js

# ==============================================================================
# CUSTOMFORM ASSETS
#
# We deliberately do NOT run "npm install && vite build" for this module.
# Its vite.config.js imports "@tailwindcss/vite" and "@vitejs/plugin-react",
# but neither package is declared in the module's package.json /
# package-lock.json -- running a build here would fail with a
# "Cannot find module '@tailwindcss/vite'" error.
#
# The module ships precompiled assets in dist/build-customform (confirmed by
# its own .module-manifest.json: requires_npm_build=false), so we just copy
# those straight into the Laravel public directory, same destination a Vite
# build would have produced.
#
# If you later change the module's frontend source and need to rebuild it,
# first add the two missing devDependencies to modules/CustomForm/package.json:
#   "@tailwindcss/vite": "^4.0.0"
#   "@vitejs/plugin-react": "^4.0.0"
# ==============================================================================

RUN mkdir -p /app/public/build-customform && cp -a /app/modules/CustomForm/dist/build-customform/. /app/public/build-customform/

# ==============================================================================
# COPY MODULE BUILDS INTO LARAVEL PUBLIC DIRECTORY
# ==============================================================================

RUN mkdir -p /app/public/build-starter26 /app/public/build-forum && cp -a /app/modules/Starter26/dist/build-starter26/. /app/public/build-starter26/ && cp -a /app/modules/Forum/dist/build-forum/. /app/public/build-forum/

# ==============================================================================
# VERIFY VITE MANIFESTS
# ==============================================================================

RUN test -f /app/public/build-starter26/manifest.json && test -f /app/public/build-forum/manifest.json && test -f /app/public/build-customform/manifest.json && echo "===== STARTER26 MANIFEST =====" && cat /app/public/build-starter26/manifest.json && echo "===== FORUM MANIFEST =====" && cat /app/public/build-forum/manifest.json && echo "===== CUSTOMFORM MANIFEST =====" && cat /app/public/build-customform/manifest.json

# ==============================================================================
# PRODUCTION STAGE
# ==============================================================================

FROM php:8.3-fpm-alpine

# ==============================================================================
# RUNTIME PACKAGES
#
# NOTE: postgresql-client and mariadb-client removed -- SQLite only now.
# "sqlite" added for SQLite support.
# ==============================================================================

RUN apk add --no-cache nginx supervisor bash unzip sqlite

# ==============================================================================
# PHP EXTENSIONS
#
# NOTE: pdo_mysql and pdo_pgsql removed -- SQLite only now.
# pdo_sqlite and sqlite3 added for SQLite support.
# ==============================================================================

COPY --from=mlocati/php-extension-installer /usr/bin/install-php-extensions /usr/local/bin/install-php-extensions

RUN chmod +x /usr/local/bin/install-php-extensions && install-php-extensions pdo_sqlite sqlite3 gd zip bcmath opcache mbstring openssl tokenizer xml ctype json fileinfo curl

# ==============================================================================
# PHP CONFIGURATION
# ==============================================================================

RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

RUN printf '%s\n' \
    'opcache.enable=1' \
    'opcache.enable_cli=1' \
    'opcache.validate_timestamps=0' \
    'opcache.memory_consumption=256' \
    'opcache.max_accelerated_files=20000' \
    'upload_max_filesize=32M' \
    'post_max_size=32M' \
    'memory_limit=256M' \
    > "$PHP_INI_DIR/conf.d/production.ini"

# ==============================================================================
# APPLICATION
# ==============================================================================

WORKDIR /var/www/html

COPY --from=builder /app /var/www/html

# ==============================================================================
# LARAVEL DIRECTORIES
# ==============================================================================

RUN mkdir -p /var/www/html/storage/app/public /var/www/html/storage/framework/cache /var/www/html/storage/framework/sessions /var/www/html/storage/framework/views /var/www/html/storage/logs /var/www/html/bootstrap/cache

# ==============================================================================
# PERMISSIONS
# ==============================================================================

RUN chown -R www-data:www-data /var/www/html && find /var/www/html -type d -exec chmod 755 {} \; && find /var/www/html -type f -exec chmod 644 {} \; && chmod -R 775 /var/www/html/storage && chmod -R 775 /var/www/html/bootstrap/cache && chmod +x /var/www/html/artisan

# ==============================================================================
# FINAL MODULE CHECK
# ==============================================================================

RUN test -f /var/www/html/modules/Starter26/module.json && test -f /var/www/html/modules/Forum/module.json && test -f /var/www/html/modules/CustomForm/module.json && test -f /var/www/html/modules/Starter26/app/Providers/Starter26ServiceProvider.php && test -f /var/www/html/modules/Forum/app/Providers/ForumServiceProvider.php && test -f /var/www/html/modules/CustomForm/app/Providers/CustomFormServiceProvider.php && test -f /var/www/html/public/build-starter26/manifest.json && test -f /var/www/html/public/build-forum/manifest.json && test -f /var/www/html/public/build-customform/manifest.json && echo "==================================================" && echo "FINAL MODULE CHECK PASSED" && echo "Starter26: OK" && echo "Forum: OK" && echo "CustomForm: OK" && echo "Starter26 Vite manifest: OK" && echo "Forum Vite manifest: OK" && echo "CustomForm Vite manifest: OK" && echo "=================================================="

# ==============================================================================
# NGINX
# ==============================================================================

RUN mkdir -p /etc/nginx/http.d

RUN cat > /etc/nginx/http.d/default.conf <<'EOF'
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

echo ""
echo "=================================================="
echo "LaraDashboard Production Startup"
echo "=================================================="

# ==============================================================================
# RENDER PORT
# ==============================================================================

PORT="${PORT:-80}"

echo "HTTP PORT: ${PORT}"

sed -i "s/listen 80 default_server;/listen ${PORT} default_server;/" /etc/nginx/http.d/default.conf

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
# ENVIRONMENT
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

chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache

find /var/www/html/modules -type d -exec chmod 755 {} \;
find /var/www/html/modules -type f -exec chmod 644 {} \;

if [ -d /var/www/html/app ]; then
    find /var/www/html/app -type d -exec chmod 755 {} \;
    find /var/www/html/app -type f -exec chmod 644 {} \;
fi

chmod -R 775 /var/www/html/storage
chmod -R 775 /var/www/html/bootstrap/cache

chmod +x /var/www/html/artisan

# ==============================================================================
# MODULE CHECK
# ==============================================================================

echo ""
echo "=================================================="
echo "MODULE CHECK"
echo "=================================================="

if [ ! -f /var/www/html/modules/Starter26/module.json ]; then
    echo "ERROR: Starter26 module is missing."
    exit 1
fi

if [ ! -f /var/www/html/modules/Forum/module.json ]; then
    echo "ERROR: Forum module is missing."
    exit 1
fi

if [ ! -f /var/www/html/modules/CustomForm/module.json ]; then
    echo "ERROR: CustomForm module is missing."
    exit 1
fi

echo "Starter26 module: FOUND"
echo "Forum module: FOUND"
echo "CustomForm module: FOUND"

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

if [ ! -f /var/www/html/public/build-customform/manifest.json ]; then
    echo "ERROR: CustomForm Vite manifest is missing."
    exit 1
fi

echo "Starter26 manifest: FOUND"
echo "Forum manifest: FOUND"
echo "CustomForm manifest: FOUND"

# ==============================================================================
# CLEAR CACHES
# ==============================================================================

echo ""
echo "Clearing Laravel caches..."

php artisan optimize:clear

# ==============================================================================
# SQLITE DATABASE FILE
#
# NOTE: added for SQLite support. If DB_CONNECTION is set to "sqlite", make
# sure the database file exists and is writable by www-data before migrations
# run. Harmless no-op for MySQL/Postgres connections.
# ==============================================================================

if [ "${DB_CONNECTION:-}" = "sqlite" ]; then
    echo ""
    echo "=================================================="
    echo "SQLITE DATABASE SETUP"
    echo "=================================================="
    mkdir -p /var/www/html/database
    touch /var/www/html/database/database.sqlite
    chown www-data:www-data /var/www/html/database/database.sqlite
    echo "SQLite database file ready at /var/www/html/database/database.sqlite"
fi

# ==============================================================================
# DATABASE MIGRATIONS
#
# Forum migrations are loaded by ForumServiceProvider.
# CustomForm migrations are loaded by CustomFormServiceProvider.
# We intentionally do NOT use migrate:fresh because that would destroy data.
#
# migrate --force is safe for existing production databases and will create
# the Forum / CustomForm tables when those modules are installed. This runs
# on EVERY boot (unlike the one-time setup below) because it needs to pick up
# schema changes from new releases, and it is cheap/fast when there is
# nothing pending.
# ==============================================================================

echo ""
echo "=================================================="
echo "RUNNING DATABASE MIGRATIONS"
echo "=================================================="

php artisan migrate --force

# ==============================================================================
# ONE-TIME SETUP: ENABLE MODULES + SEED
#
# modules_statuses.json in the repo does not have Forum or CustomForm marked
# enabled, so Laravel never registers their service providers, routes, or
# migrations on a truly fresh install -- this is why the Forum seeder
# previously failed with "Target class
# [Modules\Forum\Database\Seeders\ForumDatabaseSeeder] does not exist."
#
# This block used to run unconditionally on every boot, which meant every
# blue-green deploy re-enabled both modules and re-ran both seeders from
# scratch -- expensive (multiple full Laravel framework boots) and risky if
# either seeder is not perfectly idempotent (risk of duplicate rows on every
# deploy). It is now gated behind a marker file so it only runs once, the
# first time a container boots against a given database/storage volume.
#
# IMPORTANT: /var/www/html/storage/app must be mounted to a host path that
# persists across container recreation (e.g. `-v ~/ncs-data/storage-app:
# /var/www/html/storage/app` in the deploy script) or this marker will never
# survive a blue-green swap and this block will re-run every deploy anyway.
# ==============================================================================

INSTALL_MARKER=/var/www/html/storage/app/.installed

if [ ! -f "$INSTALL_MARKER" ]; then
    echo ""
    echo "=================================================="
    echo "FIRST BOOT: ENABLING MODULES"
    echo "=================================================="

    php artisan module:enable Forum
    php artisan module:enable CustomForm

    php artisan module:list || true

    echo ""
    echo "=================================================="
    echo "FIRST BOOT: FORUM DATABASE SEED"
    echo "=================================================="

    php artisan db:seed --class="Modules\Forum\Database\Seeders\ForumDatabaseSeeder" --force

    echo ""
    echo "=================================================="
    echo "FIRST BOOT: CUSTOMFORM DATABASE SEED"
    echo "=================================================="

    php artisan db:seed --class="Modules\CustomForm\Database\Seeders\CustomFormDatabaseSeeder" --force

    mkdir -p "$(dirname "$INSTALL_MARKER")"
    date -u +"%Y-%m-%dT%H:%M:%SZ" > "$INSTALL_MARKER"

    echo ""
    echo "First-boot setup complete. Marker written to $INSTALL_MARKER."
else
    echo ""
    echo "=================================================="
    echo "MODULE SETUP: SKIPPED (already installed)"
    echo "=================================================="
    echo "Marker found at $INSTALL_MARKER ($(cat "$INSTALL_MARKER" 2>/dev/null || echo unknown))"
fi

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

chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache

chmod -R 775 /var/www/html/storage /var/www/html/bootstrap/cache

# ==============================================================================
# FINAL STATUS
# ==============================================================================

echo ""
echo "=================================================="
echo "LARADASHBOARD READY"
echo "=================================================="
echo "Starter26: INSTALLED"
echo "Forum: INSTALLED"
echo "CustomForm: INSTALLED"
echo "Starter26 assets: BUILT"
echo "Forum assets: BUILT"
echo "CustomForm assets: BUILT"
echo "Database migrations: COMPLETE"
echo "Nginx: READY"
echo "PHP-FPM: READY"
echo "=================================================="
echo ""

# ==============================================================================
# START SERVICES
# ==============================================================================

exec /usr/bin/supervisord -c /etc/supervisord.conf
EOF

RUN chmod +x /usr/local/bin/entrypoint.sh

# ==============================================================================
# RENDER
# ==============================================================================

EXPOSE 80

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
