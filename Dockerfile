# ==============================================================================
# STAGE 1: Build PHP dependencies and frontend assets
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

# Copy the entire Laravel application
COPY . .

# ------------------------------------------------------------------------------
# Composer
# ------------------------------------------------------------------------------

COPY --from=composer:2.7 /usr/bin/composer /usr/local/bin/composer

# ------------------------------------------------------------------------------
# Verify modules that are actually present
#
# DO NOT create a fake Starter26 directory.
# If Starter26 is eventually added to the repository, this build will show it.
# ------------------------------------------------------------------------------

RUN echo "==================================================" \
    && echo "MODULES FOUND IN SOURCE TREE" \
    && echo "==================================================" \
    && find /app/modules -maxdepth 2 -type f -print 2>/dev/null || true

RUN echo "==================================================" \
    && echo "MODULE DIRECTORIES" \
    && echo "==================================================" \
    && find /app/modules -maxdepth 2 -type d -print 2>/dev/null || true

# ------------------------------------------------------------------------------
# Install PHP dependencies
# ------------------------------------------------------------------------------

RUN composer install \
    --no-interaction \
    --prefer-dist \
    --optimize-autoloader \
    --ignore-platform-reqs

# ------------------------------------------------------------------------------
# Install main frontend dependencies
# ------------------------------------------------------------------------------

RUN npm ci

# ------------------------------------------------------------------------------
# Build main frontend
# ------------------------------------------------------------------------------

RUN npm run build


# ==============================================================================
# STAGE 2: Production application
# ==============================================================================

FROM php:8.3-fpm-alpine

# ------------------------------------------------------------------------------
# Production services
# ------------------------------------------------------------------------------

RUN apk add --no-cache \
    nginx \
    supervisor \
    bash \
    postgresql-client \
    mariadb-client

# ------------------------------------------------------------------------------
# PHP extension installer
# ------------------------------------------------------------------------------

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

# ------------------------------------------------------------------------------
# PHP production configuration
# ------------------------------------------------------------------------------

RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

RUN echo "opcache.enable_cli=1" \
        >> "$PHP_INI_DIR/conf.d/opcache.ini"

RUN mkdir -p "$PHP_INI_DIR/conf.d"

RUN cat <<'EOF' > "$PHP_INI_DIR/conf.d/uploads.ini"
upload_max_filesize=32M
post_max_size=32M
EOF

# ------------------------------------------------------------------------------
# Application
# ------------------------------------------------------------------------------

WORKDIR /var/www/html

COPY --from=builder /app /var/www/html

# ------------------------------------------------------------------------------
# Make sure Laravel runtime directories exist
# ------------------------------------------------------------------------------

RUN mkdir -p \
    /var/www/html/storage/app/public \
    /var/www/html/storage/framework/cache \
    /var/www/html/storage/framework/sessions \
    /var/www/html/storage/framework/views \
    /var/www/html/storage/logs \
    /var/www/html/bootstrap/cache

# ------------------------------------------------------------------------------
# Show modules that actually made it into the production image
# ------------------------------------------------------------------------------

RUN echo "==================================================" \
    && echo "MODULES IN PRODUCTION IMAGE" \
    && echo "==================================================" \
    && find /var/www/html/modules -maxdepth 2 -type d -print 2>/dev/null || true

# ------------------------------------------------------------------------------
# Review module diagnostics
#
# This is intentionally included because your Review module currently throws:
#
# Route [admin.review.reviews.index] not defined.
#
# The Render BUILD LOG will show us exactly what was copied into the image.
# ------------------------------------------------------------------------------

RUN echo "==================================================" \
    && echo "REVIEW MODULE DIAGNOSTICS" \
    && echo "==================================================" \
    && if [ -d /var/www/html/modules/Review ]; then \
         echo "Review module FOUND"; \
         find /var/www/html/modules/Review -maxdepth 4 -type f -print | sort; \
       else \
         echo "Review module NOT FOUND"; \
       fi

# ------------------------------------------------------------------------------
# Nginx configuration
# ------------------------------------------------------------------------------

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

# ------------------------------------------------------------------------------
# Supervisor configuration
# ------------------------------------------------------------------------------

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

# ------------------------------------------------------------------------------
# Entrypoint
# ------------------------------------------------------------------------------

RUN cat <<'EOF' > /usr/local/bin/entrypoint.sh
#!/bin/sh

set -e

cd /var/www/html

echo "=================================================="
echo "Laravel production startup"
echo "=================================================="

# ------------------------------------------------------------------------------
# APP_KEY
#
# IMPORTANT:
# Configure APP_KEY in Render Environment Variables.
#
# Do NOT generate a new APP_KEY every time the container starts.
# ------------------------------------------------------------------------------

if [ -z "${APP_KEY:-}" ]; then
    echo ""
    echo "ERROR: APP_KEY is not configured."
    echo ""
    echo "Add APP_KEY to the Render Environment Variables."
    echo "Example:"
    echo ""
    echo "APP_KEY=base64:your-generated-key"
    echo ""
    exit 1
fi

echo "APP_KEY is configured."

# ------------------------------------------------------------------------------
# Create .env only if the application requires the physical file.
#
# Render environment variables are the source of truth.
# ------------------------------------------------------------------------------

if [ ! -f /var/www/html/.env ]; then

    if [ -f /var/www/html/.env.example ]; then
        cp /var/www/html/.env.example /var/www/html/.env
    else
        touch /var/www/html/.env
    fi

fi

# Make sure APP_KEY exists in .env for packages that explicitly read it.
if grep -q '^APP_KEY=' /var/www/html/.env; then

    sed -i "s|^APP_KEY=.*|APP_KEY=${APP_KEY}|" /var/www/html/.env

else

    echo "APP_KEY=${APP_KEY}" >> /var/www/html/.env

fi

# ------------------------------------------------------------------------------
# Runtime permissions
# ------------------------------------------------------------------------------

echo "Applying runtime permissions..."

chown -R www-data:www-data \
    /var/www/html/storage \
    /var/www/html/bootstrap/cache

chmod -R 775 \
    /var/www/html/storage \
    /var/www/html/bootstrap/cache

# ------------------------------------------------------------------------------
# Clear ALL old Laravel caches first.
#
# This is particularly important when modules are present.
# ------------------------------------------------------------------------------

echo "Clearing Laravel caches..."

php artisan optimize:clear

# ------------------------------------------------------------------------------
# Show Laravel/module information in Render logs.
# ------------------------------------------------------------------------------

echo "=================================================="
echo "MODULE STATUS"
echo "=================================================="

php artisan module:list || true

# ------------------------------------------------------------------------------
# Show Review routes if the Review module exists.
# ------------------------------------------------------------------------------

echo "=================================================="
echo "REVIEW ROUTES"
echo "=================================================="

php artisan route:list 2>/dev/null | grep -i review || true

# ------------------------------------------------------------------------------
# Cache configuration AFTER APP_KEY and modules are available.
# ------------------------------------------------------------------------------

echo "Caching Laravel configuration..."

php artisan config:cache

echo "Caching Laravel routes..."

php artisan route:cache

echo "Caching Laravel views..."

php artisan view:cache

# ------------------------------------------------------------------------------
# Storage link
# ------------------------------------------------------------------------------

echo "Creating public storage link..."

php artisan storage:link --force || true

# ------------------------------------------------------------------------------
# Final permissions
# ------------------------------------------------------------------------------

chown -R www-data:www-data \
    /var/www/html/storage \
    /var/www/html/bootstrap/cache

chmod -R 775 \
    /var/www/html/storage \
    /var/www/html/bootstrap/cache

echo "=================================================="
echo "Laravel initialization complete"
echo "Starting Nginx + PHP-FPM"
echo "=================================================="

# ------------------------------------------------------------------------------
# Start Supervisor
# ------------------------------------------------------------------------------

exec /usr/bin/supervisord -c /etc/supervisord.conf
EOF

RUN chmod +x /usr/local/bin/entrypoint.sh

# ------------------------------------------------------------------------------
# Render web service
# ------------------------------------------------------------------------------

EXPOSE 80

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
