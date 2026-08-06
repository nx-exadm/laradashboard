# ==============================================================================
# STAGE 1: Install PHP Dependencies & Build Frontend Assets
# ==============================================================================
FROM php:8.3-fpm-alpine AS builder

# Install system dependencies, nodejs, npm, and database development headers
RUN apk add --no-cache \
    nodejs \
    npm \
    libpng-dev \
    libjpeg-turbo-dev \
    freetype-dev \
    zip \
    libzip-dev \
    postgresql-dev \
    mariadb-dev \
    git

# Configure and compile core PHP extensions for the builder environment
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install pdo_mysql pdo_pgsql gd zip bcmath

WORKDIR /app
COPY . .

# Inject the official Composer binary directly from Docker Hub (Prevents Download Failures)
COPY --from=composer:2.7 /usr/bin/composer /usr/local/bin/composer

# Install structural back-end PHP dependencies
RUN composer install --no-interaction --prefer-dist --optimize-autoloader

# Compile the public Vite frontend assets
RUN npm ci && npm run build

# ==============================================================================
# STAGE 2: Highly Optimized Production Application Environment
# ==============================================================================
FROM php:8.3-fpm-alpine

# Install minimal production system runtime binaries
RUN apk add --no-cache \
    nginx \
    supervisor \
    bash \
    libpng \
    libjpeg-turbo \
    freetype \
    libzip \
    postgresql-libs \
    mariadb-connector-c

# Compile required production PHP extensions and strip out build tools immediately
RUN apk add --no-cache --virtual .build-deps postgresql-dev mariadb-dev libpng-dev libjpeg-turbo-dev freetype-dev libzip-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install pdo_mysql pdo_pgsql gd zip bcmath opcache \
    && apk del .build-deps

# Configure optimal production caching adjustments inside PHP
RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini" \
    && echo "opcache.enable_cli=1" >> "$PHP_INI_DIR/conf.d/docker-php-ext-opcache.ini" \
    && echo "upload_max_filesize=32M" >> "$PHP_INI_DIR/conf.d/uploads.ini" \
    && echo "post_max_size=32M" >> "$PHP_INI_DIR/conf.d/uploads.ini"

WORKDIR /var/www/html

# Transfer the completed codebase assembly from Stage 1 into production workspace
COPY --from=builder /app /var/www/html

# Grant secure structural permissions to Laravel storage maps
RUN chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache \
    && chmod -R 775 /var/www/html/storage /var/www/html/bootstrap/cache

# Inject the Nginx web routing rules inline
RUN echo 'server { \
    listen 80 default_server; \
    root /var/www/html/public; \
    index index.php index.html; \
    charset utf-8; \
    location / { \
        try_files $uri $uri/ /index.php?$query_string; \
    } \
    location = /favicon.ico { access_log off; log_not_found off; } \
    location = /robots.txt  { access_log off; log_not_found off; } \
    error_page 404 /index.php; \
    location ~ \.php$ { \
        fastcgi_pass 127.0.0.1:9000; \
        fastcgi_index index.php; \
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name; \
        include fastcgi_params; \
    } \
    location ~ /\.(?!well-known).* { \
        deny all; \
    } \
}' > /etc/nginx/http.d/default.conf

# Configure Supervisor orchestration to manage Nginx and PHP concurrently
RUN echo '[supervisord] \n\
nodaemon=true \n\
user=root \n\
logfile=/dev/null \n\
logfile_maxbytes=0 \n\
\n\
[program:php-fpm] \n\
command=php-fpm \n\
stdout_logfile=/dev/stdout \n\
stdout_logfile_maxbytes=0 \n\
stderr_logfile=/dev/stderr \n\
stderr_logfile_maxbytes=0 \n\
\n\
[program:nginx] \n\
command=nginx -g "daemon off;" \n\
stdout_logfile=/dev/stdout \n\
stdout_logfile_maxbytes=0 \n\
stderr_logfile=/dev/stderr \n\
stderr_logfile_maxbytes=0' > /etc/supervisord.conf

# Create the automated execution script to configure caches and migrations at launch
RUN echo '#!/bin/sh \n\
echo "Optimizing framework application run-caches..." \n\
php artisan config:cache \n\
php artisan route:cache \n\
php artisan view:cache \n\
\n\
echo "Executing active structural database schemas against Aiven..." \n\
php artisan migrate --force \n\
\n\
echo "Enabling internal CMS feature modules..." \n\
php artisan module:enable \n\
\n\
echo "Spinning up process management ecosystem..." \n\
exec /usr/bin/supervisord -c /etc/supervisord.conf' > /usr/local/bin/entrypoint.sh \
    && chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 80
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
