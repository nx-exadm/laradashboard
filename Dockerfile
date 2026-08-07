# ==============================================================================

# LARADASHBOARD + STARTER26

# Production Docker image for Render

# ==============================================================================

# ==============================================================================

# STAGE 1: BUILD

# ==============================================================================

FROM php:8.3-fpm-alpine AS builder

# ==============================================================================

# BUILD DEPENDENCIES

# ==============================================================================

RUN apk add --no-cache 
nodejs 
npm 
zip 
unzip 
libzip-dev 
git 
curl

WORKDIR /app

# ==============================================================================

# COPY APPLICATION

# ==============================================================================

COPY . .

# ==============================================================================

# INSTALL STARTER26 FROM ZIP

#

# The ZIP must be in the ROOT of the GitHub repository:

#

# starter26-v1.0.4.zip

#

# Expected ZIP structure:

#

# Starter26/

# ├── app/

# ├── config/

# ├── database/

# ├── dist/

# ├── resources/

# ├── routes/

# ├── module.json

# ├── package.json

# └── ...

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
mkdir -p /app/modules/Starter26; 
cp -a /tmp/starter26-install/. /app/modules/Starter26/; 
else 
echo "ERROR: Starter26 module.json was not found inside ZIP"; 
find /tmp/starter26-install -maxdepth 5 -type f | sort; 
exit 1; 
fi; 
rm -rf /tmp/starter26-install; 
rm -f /app/starter26-v1.0.4.zip

# ==============================================================================

# VERIFY STARTER26

# ==============================================================================

RUN set -eux; 
test -f /app/modules/Starter26/module.json; 
echo "=================================================="; 
echo "STARTER26 MODULE MANIFEST"; 
echo "=================================================="; 
cat /app/modules/Starter26/module.json; 
echo ""; 
echo "=================================================="; 
echo "STARTER26 FILES"; 
echo "=================================================="; 
find /app/modules/Starter26 -maxdepth 4 -type f | sort

# ==============================================================================

# VERIFY STARTER26 PRECOMPILED VITE BUILD

#

# The real Starter26 ZIP contains:

#

# modules/Starter26/dist/build-starter26/

# ├── manifest.json

# └── assets/

#

# Laravel's @vite(..., 'build-starter26') expects the manifest at:

#

# public/build-starter26/manifest.json

# ==============================================================================

RUN set -eux; 
echo "=================================================="; 
echo "STARTER26 PRECOMPILED BUILD"; 
echo "=================================================="; 
test -f /app/modules/Starter26/dist/build-starter26/manifest.json; 
cat /app/modules/Starter26/dist/build-starter26/manifest.json; 
echo ""; 
echo "Starter26 Vite build FOUND."

# ==============================================================================

# COMPOSER

# ==============================================================================

COPY --from=composer:2.7 /usr/bin/composer /usr/local/bin/composer

# ==============================================================================

# INSTALL LARAVEL DEPENDENCIES

# ==============================================================================

RUN composer install 
--no-interaction 
--prefer-dist 
--optimize-autoloader 
--ignore-platform-reqs

# ==============================================================================

# REBUILD AUTOLOADER

# ==============================================================================

RUN composer dump-autoload 
--optimize 
--no-interaction

# ==============================================================================

# MAIN APPLICATION FRONTEND

# ==============================================================================

RUN npm ci

RUN npm run build

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

# CRITICAL STARTER26 VITE ASSET FIX

#

# Starter26 ships with its own compiled production assets:

#

# modules/Starter26/dist/build-starter26/

#

# Laravel's @vite() directive with the "build-starter26" build name looks for:

#

# public/build-starter26/manifest.json

#

# Therefore copy the compiled Starter26 distribution into Laravel's public

# directory.

# ==============================================================================

RUN set -eux; 
test -f /var/www/html/modules/Starter26/dist/build-starter26/manifest.json; 
mkdir -p /var/www/html/public/build-starter26; 
cp -a /var/www/html/modules/Starter26/dist/build-starter26/. 
/var/www/html/public/build-starter26/; 
test -f /var/www/html/public/build-starter26/manifest.json; 
echo "=================================================="; 
echo "STARTER26 PUBLIC VITE BUILD"; 
echo "=================================================="; 
find /var/www/html/public/build-starter26 -maxdepth 2 -type f | sort; 
echo ""; 
echo "Starter26 public Vite manifest FOUND."

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

#

# PHP source files remain readable by PHP-FPM.

# Laravel writable directories are writable by www-data.

# ==============================================================================

RUN set -eux; 
chown -R www-data:www-data /var/www/html; 
find /var/www/html -type d -exec chmod 755 {} ;; 
find /var/www/html -type f -exec chmod 644 {} ;; 
chmod -R 775 /var/www/html/storage; 
chmod -R 775 /var/www/html/bootstrap/cache; 
chmod +x /var/www/html/artisan

# ==============================================================================

# VERIFY STARTER26 AFTER PERMISSIONS

# ==============================================================================

RUN set -eux; 
test -f /var/www/html/modules/Starter26/module.json; 
test -f /var/www/html/modules/Starter26/app/Providers/Starter26ServiceProvider.php; 
test -f /var/www/html/modules/Starter26/app/Providers/Starter26LivewireServiceProvider.php; 
test -f /var/www/html/public/build-starter26/manifest.json; 
echo "=================================================="; 
echo "FINAL STARTER26 CHECK"; 
echo "=================================================="; 
ls -la /var/www/html/modules/Starter26; 
echo ""; 
echo "Starter26 Providers:"; 
ls -la /var/www/html/modules/Starter26/app/Providers; 
echo ""; 
echo "Starter26 Vite Manifest:"; 
ls -la /var/www/html/public/build-starter26/manifest.json

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
echo ""

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

# PUT APP_KEY INTO .ENV

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

chown -R www-data:www-data 
/var/www/html/storage 
/var/www/html/bootstrap/cache

find /var/www/html/modules -type d -exec chmod 755 {} ;
find /var/www/html/modules -type f -exec chmod 644 {} ;

if [ -d /var/www/html/app ]; then
find /var/www/html/app -type d -exec chmod 755 {} ;
find /var/www/html/app -type f -exec chmod 644 {} ;
fi

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

# STARTER26 VITE BUILD CHECK

# ==============================================================================

echo ""
echo "=================================================="
echo "STARTER26 VITE BUILD CHECK"
echo "=================================================="

if [ ! -f /var/www/html/public/build-starter26/manifest.json ]; then
echo "ERROR: Starter26 Vite manifest is missing."
echo ""
echo "Expected:"
echo "/var/www/html/public/build-starter26/manifest.json"
echo ""
exit 1
fi

echo "Starter26 Vite manifest: FOUND"

echo ""
echo "Starter26 assets:"
find /var/www/html/public/build-starter26 -maxdepth 2 -type f | sort

# ==============================================================================

# CLEAR LARAVEL CACHES

# ==============================================================================

echo ""
echo "=================================================="
echo "CLEARING LARAVEL CACHES"
echo "=================================================="

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

# STORAGE LINK

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

# FINAL STARTER26 CHECK

# ==============================================================================

echo ""
echo "=================================================="
echo "FINAL STARTER26 CHECK"
echo "=================================================="

test -f /var/www/html/modules/Starter26/module.json
test -f /var/www/html/public/build-starter26/manifest.json

echo "Starter26 module: OK"
echo "Starter26 Vite manifest: OK"

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
