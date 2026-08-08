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

# Copy application

# ------------------------------------------------------------------------------

COPY . .

# ==============================================================================

# INSTALL STARTER26

# ==============================================================================

RUN set -eux; 
echo "=================================================="; 
echo "Installing Starter26"; 
echo "=================================================="; 
test -f /app/starter26-v1.0.4.zip; 
mkdir -p /app/modules; 
rm -rf /app/modules/Starter26; 
rm -rf /tmp/starter26-install; 
mkdir -p /tmp/starter26-install; 
unzip -q /app/starter26-v1.0.4.zip -d /tmp/starter26-install; 
if [ -f /tmp/starter26-install/Starter26/module.json ]; then 
mv /tmp/starter26-install/Starter26 /app/modules/Starter26; 
elif [ -f /tmp/starter26-install/module.json ]; then 
mv /tmp/starter26-install /app/modules/Starter26; 
else 
echo "ERROR: Starter26 module.json was not found inside ZIP"; 
find /tmp/starter26-install -maxdepth 5 -type f | sort; 
exit 1; 
fi; 
rm -f /app/starter26-v1.0.4.zip; 
test -f /app/modules/Starter26/module.json; 
echo "Starter26 installed successfully."

# ==============================================================================

# INSTALL FORUM MODULE

# ==============================================================================

RUN set -eux; 
echo "=================================================="; 
echo "Searching for Forum module ZIP"; 
echo "=================================================="; 
mkdir -p /app/modules; 
FORUM_ZIP="$(find /app -maxdepth 1 -type f -iname 'forum*.zip' | head -n 1)"; 
if [ -z "$FORUM_ZIP" ]; then 
echo "ERROR: Forum ZIP was not found in repository root."; 
echo "Expected a file such as forum.zip or forum-v1.0.0.zip"; 
echo "Available ZIP files:"; 
find /app -maxdepth 1 -type f -iname '*.zip' -print | sort; 
exit 1; 
fi; 
echo "Forum ZIP found: $FORUM_ZIP"; 
rm -rf /app/modules/Forum; 
rm -rf /tmp/forum-install; 
mkdir -p /tmp/forum-install; 
unzip -q "$FORUM_ZIP" -d /tmp/forum-install; 
echo "Forum ZIP contents:"; 
find /tmp/forum-install -maxdepth 4 -type f | sort; 
if [ -f /tmp/forum-install/Forum/module.json ]; then 
mv /tmp/forum-install/Forum /app/modules/Forum; 
elif [ -f /tmp/forum-install/module.json ]; then 
mv /tmp/forum-install /app/modules/Forum; 
else 
FORUM_DIR="$(find /tmp/forum-install -mindepth 1 -maxdepth 1 -type d | head -n 1)"; 
if [ -n "$FORUM_DIR" ] && [ -f "$FORUM_DIR/module.json" ]; then 
mv "$FORUM_DIR" /app/modules/Forum; 
else 
echo "ERROR: Forum module.json was not found inside ZIP."; 
echo "The ZIP structure does not contain a recognizable Forum module."; 
exit 1; 
fi; 
fi; 
rm -f "$FORUM_ZIP"; 
test -f /app/modules/Forum/module.json; 
echo "Forum installed successfully."

# ==============================================================================

# VERIFY MODULES

# ==============================================================================

RUN set -eux; 
echo "=================================================="; 
echo "MODULE VERIFICATION"; 
echo "=================================================="; 
echo ""; 
echo "===== STARTER26 MANIFEST ====="; 
cat /app/modules/Starter26/module.json; 
echo ""; 
echo "===== FORUM MANIFEST ====="; 
cat /app/modules/Forum/module.json; 
echo ""; 
echo "===== MODULE DIRECTORIES ====="; 
find /app/modules -maxdepth 2 -type f -name module.json -print | sort

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

# Build all frontend assets defined by the application's Vite configuration.

RUN npm run build

# Verify the Starter26 Vite manifest exists.

RUN set -eux; 
echo "=================================================="; 
echo "VITE BUILD VERIFICATION"; 
echo "=================================================="; 
if [ -f /app/public/build-starter26/manifest.json ]; then 
echo "Starter26 Vite manifest: FOUND"; 
cat /app/public/build-starter26/manifest.json; 
else 
echo "WARNING: Starter26 Vite manifest was not generated."; 
echo "Checking available build directories:"; 
find /app/public -maxdepth 3 -type f -name manifest.json -print | sort || true; 
fi

# ==============================================================================

# STAGE 2: PRODUCTION

# ==============================================================================

FROM php:8.3-fpm-alpine

# ==============================================================================

# RUNTIME PACKAGES

# ==============================================================================

RUN apk add --no-cache 
nginx 
supervisor 
bash 
postgresql-client 
mariadb-client 
unzip

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

RUN mkdir -p 
/var/www/html/storage/app/public 
/var/www/html/storage/framework/cache 
/var/www/html/storage/framework/sessions 
/var/www/html/storage/framework/views 
/var/www/html/storage/logs 
/var/www/html/bootstrap/cache

# ==============================================================================

# FILE OWNERSHIP / PERMISSIONS

# ==============================================================================

RUN chown -R www-data:www-data /var/www/html 
&& find /var/www/html -type d -exec chmod 755 {} ; 
&& find /var/www/html -type f -exec chmod 644 {} ; 
&& chmod -R 775 /var/www/html/storage 
&& chmod -R 775 /var/www/html/bootstrap/cache 
&& chmod +x /var/www/html/artisan

# ==============================================================================

# FINAL MODULE VERIFICATION

# ==============================================================================

RUN set -eux; 
echo "=================================================="; 
echo "FINAL MODULE CHECK"; 
echo "=================================================="; 
test -f /var/www/html/modules/Starter26/module.json; 
test -f /var/www/html/modules/Forum/module.json; 
test -f /var/www/html/modules/Starter26/app/Providers/Starter26ServiceProvider.php; 
echo "Starter26: FOUND"; 
echo "Forum: FOUND"; 
echo ""; 
echo "Starter26 providers:"; 
ls -la /var/www/html/modules/Starter26/app/Providers; 
echo ""; 
echo "Forum structure:"; 
find /var/www/html/modules/Forum -maxdepth 3 -type f | sort | head -200

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
echo "LaraDashboard Production Startup"
echo "=================================================="

# ==============================================================================

# RENDER PORT

# ==============================================================================

PORT="${PORT:-80}"

echo "HTTP PORT: ${PORT}"

sed -i "s/listen 80 default_server;/listen ${PORT} default_server;/" 
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

chown -R www-data:www-data 
/var/www/html/storage 
/var/www/html/bootstrap/cache

find /var/www/html/modules -type d -exec chmod 755 {} ;
find /var/www/html/modules -type f -exec chmod 644 {} ;

find /var/www/html/app -type d -exec chmod 755 {} ; 2>/dev/null || true
find /var/www/html/app -type f -exec chmod 644 {} ; 2>/dev/null || true

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

echo ""
echo "Forum module manifest:"
cat /var/www/html/modules/Forum/module.json

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

# ROUTES

# ==============================================================================

echo ""
echo "=================================================="
echo "STARTER26 + FORUM ROUTES"
echo "=================================================="

php artisan route:list 2>/dev/null | grep -Ei 'starter26|forum' || true

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

chown -R www-data:www-data 
/var/www/html/storage 
/var/www/html/bootstrap/cache

chmod -R 775 
/var/www/html/storage 
/var/www/html/bootstrap/cache

# ==============================================================================

# FINAL VITE CHECK

# ==============================================================================

echo ""
echo "=================================================="
echo "VITE MANIFEST CHECK"
echo "=================================================="

if [ -f /var/www/html/public/build-starter26/manifest.json ]; then
echo "Starter26 Vite manifest: FOUND"
else
echo "WARNING: Starter26 Vite manifest NOT FOUND"
echo "Available manifests:"
find /var/www/html/public -type f -name manifest.json -print 2>/dev/null || true
fi

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
