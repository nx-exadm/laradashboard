# ==============================================================================
# STAGE 1: Install PHP Dependencies & Build Frontend Assets
# ==============================================================================
FROM php:8.3-fpm-alpine AS builder

# Set up the community repository for pre-compiled PHP extensions
RUN apk add --no-cache --repository=http://alpinelinux.org \
    nodejs \
    npm \
    zip \
    libzip-dev \
    git \
    curl

WORKDIR /app
COPY . .

# Inject the official Composer binary directly from Docker Hub 
COPY --from=composer:2.7 /usr/bin/composer /usr/local/bin/composer

# Install backend dependencies without needing full extension runtimes in stage 1
RUN composer install --no-interaction --prefer-dist --optimize-autoloader --ignore-platform-reqs

# Compile the public Vite frontend assets
RUN npm ci && npm run build

# ==============================================================================
# STAGE 2: High-Speed Production Application Environment (No Compiling)
# ==============================================================================
FROM php:8.3-fpm-alpine

# Install Nginx, Supervisor, Bash, and native Postgres/MySQL runtime clients
RUN apk add --no-cache \
    nginx \
    supervisor \
    bash \
    postgresql-client \
    mariadb-client

# Install PRE-COMPILED PHP extensions directly via Alpine packages (Takes ~3 seconds)
RUN apk add --no-cache --repository=http://alpinelinux.org \
    php83-pdo_mysql \
    php83-pdo_pgsql \
    php83-gd \
    php83-zip \
    php83-bcmath \
    php83-opcache

# Symlink Alpine's native extensions so standard PHP-FPM reads them natively
RUN ln -sf /usr/lib/php83/modules/*.so /usr/local/lib/php/extensions/no-debug-non-zts-20230831/ \
    && echo "extension=pdo_mysql.so" > /usr/local/etc/php/conf.d/ext-pdo_mysql.ini \
    && echo "extension=pdo_pgsql.so" > /usr/local/etc/php/conf.d/ext-pdo_pgsql.ini \
    && echo "extension=gd.so" > /usr/local/etc/php/conf.d/ext-gd.ini \
    && echo "extension=zip.so" > /usr/local/etc/php/conf.d/ext-zip.ini \
    && echo "extension=bcmath.so" > /usr/local/etc/php/conf.d/ext-bcmath.ini \
    && echo "zend_extension=opcache.so" > /usr/local/etc/php/conf.d/ext-opcache.ini

# Configure production optimizations
RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini" \
    && echo "opcache.enable_cli=1" >> /usr/local/etc/php/conf.d/ext-opcache.ini \
    && echo "upload_max_filesize=32M" >> "$PHP_INI_DIR/conf.d/uploads.ini" \
    && echo "post_max_size=32M" >> "$PHP_INI_DIR/conf.d/uploads.ini"

WORKDIR /var/www/html

# Transfer completed build layers from Stage 1
COPY --from=builder /app /var/www/html

# Set exact permissions for Laravel deployment structures
RUN chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache \
    && chmod -R 775 /var/www/html/storage /var/www/html/bootstrap/cache

# Inject Nginx configurations
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

# Inject Supervisor orchestration configs
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

# Create the launch automation entrypoint script
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
