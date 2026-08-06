# ==============================================================================
# STAGE 1: Build Frontend Assets
# ==============================================================================
FROM node:20-alpine AS asset-builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# ==============================================================================
# STAGE 2: Production PHP & Nginx Environment
# ==============================================================================
FROM php:8.3-fpm-alpine

# Install production system dependencies, Nginx, and Supervisor
RUN apk add --no-cache \
    nginx \
    supervisor \
    bash \
    libpng-dev \
    libjpeg-turbo-dev \
    freetype-dev \
    zip \
    libzip-dev \
    postgresql-client \
    mariadb-client

# Configure and install PHP extensions required by Laravel and Lara Dashboard
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install pdo_mysql pdo_pgsql gd zip bcmath opcache

# Configure custom optimized production PHP settings
RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini" \
    && echo "opcache.enable_cli=1" >> "$PHP_INI_DIR/conf.d/docker-php-ext-opcache.ini" \
    && echo "upload_max_filesize=32M" >> "$PHP_INI_DIR/conf.d/uploads.ini" \
    && echo "post_max_size=32M" >> "$PHP_INI_DIR/conf.d/uploads.ini"

# Establish application directory
WORKDIR /var/www/html

# Copy application source code
COPY . .

# Copy compiled frontend assets from Stage 1
COPY --from=asset-builder /app/public/build ./public/build

# Install Composer binaries and pull production PHP dependencies
RUN curl -sS https://getcomposer.org | php -- --install-dir=/usr/local/bin --filename=composer \
    && composer install --no-dev --no-interaction --prefer-dist --optimize-autoloader

# Set structural permissions so Laravel can write logs, sessions, and caches
RUN chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache \
    && chmod -R 775 /var/www/html/storage /var/www/html/bootstrap/cache

# Write the custom Nginx server configuration inline
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

# Write the custom Supervisor configuration to orchestrate Nginx and PHP-FPM together
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

# Create the startup entrypoint script directly inside the image
RUN echo '#!/bin/sh \n\
echo "Running optimization and runtime caches..." \n\
php artisan config:cache \n\
php artisan route:cache \n\
php artisan view:cache \n\
\n\
echo "Executing database schema migrations on Aiven..." \n\
php artisan migrate --force \n\
\n\
echo "Bootstrapping CMS Modules..." \n\
php artisan module:enable \n\
\n\
echo "Starting Application Environment..." \n\
exec /usr/bin/supervisord -c /etc/supervisord.conf' > /usr/local/bin/entrypoint.sh \
    && chmod +x /usr/local/bin/entrypoint.sh

# Render binds to port 80 dynamically
EXPOSE 80

# Execute the entrypoint script on boot
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
