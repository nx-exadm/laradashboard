# ==============================================================================
# STAGE 1: Install PHP Dependencies & Build Assets
# ==============================================================================
FROM php:8.3-fpm-alpine AS builder

# Install system dependencies, nodejs, npm, and postgresql development headers
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
    curl \
    git

# Configure and compile PHP extensions so we can execute artisan commands if needed
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install pdo_mysql pdo_pgsql gd zip bcmath

WORKDIR /app
COPY . .

# Step A: Install Composer binaries and download vendor dependencies (CRITICAL FOR VITE)
RUN curl -sS https://getcomposer.org | php -- --install-dir=/usr/local/bin --filename=composer \
    && composer install --no-interaction --prefer-dist --optimize-autoloader

# Step B: Compile frontend assets now that livewire files exist in /vendor
RUN npm ci && npm run build

# ==============================================================================
# STAGE 2: Optimized Production Runtime
# ==============================================================================
FROM php:8.3-fpm-alpine

# Install minimal production run-time binaries (no heavy build tools)
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

# Re-install compiled extensions quickly from fresh binaries
RUN apk add --no-cache --virtual .build-deps postgresql-dev mariadb-dev libpng-dev libjpeg-turbo-dev freetype-dev libzip-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install pdo_mysql pdo_pgsql gd zip bcmath opcache \
    && apk del .build-deps

# Configure custom optimized production PHP settings
RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini" \
    && echo "opcache.enable_cli=1" >> "$PHP_INI_DIR/conf.d/docker-php-ext-opcache.ini" \
    && echo "upload_max_filesize=32M" >> "$PHP_INI_DIR/conf.d/uploads.ini" \
    && echo "post_max_size=32M" >> "$PHP_INI_DIR/conf.d/uploads.ini"

WORKDIR /var/www/html

# Copy application and pre-compiled structural code from stage 1
COPY --from=builder /app /var/www/html

# Set exact structural permissions for Laravel deployment
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

# Write the custom Supervisor configuration to orchestrate systems together
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

# Create the automated startup engine script
RUN echo '#!/bin/sh \n\
echo "Optimizing applications caches..." \n\
php artisan config:cache \n\
php artisan route:cache \n\
php artisan view:cache \n\
\n\
echo "Running schema migrations against Aiven..." \n\
php artisan migrate --force \n\
\n\
echo "Booting framework modules..." \n\
php artisan module:enable \n\
\n\
echo "Launching Supervisor process stack..." \n\
exec /usr/bin/supervisord -c /etc/supervisord.conf' > /usr/local/bin/entrypoint.sh \
    && chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 80
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
