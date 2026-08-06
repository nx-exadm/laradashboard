# ==============================================================================
# STAGE 1: Install PHP Dependencies & Build Frontend Assets
# ==============================================================================
FROM php:8.3-fpm-alpine AS builder

RUN apk add --no-cache nodejs npm zip libzip-dev git curl

WORKDIR /app
COPY . .

# Secure a pre-compiled Composer binary cleanly
COPY --from=composer:2.7 /usr/bin/composer /usr/local/bin/composer

# Install backend files safely ignoring local machine requirements
RUN composer install --no-interaction --prefer-dist --optimize-autoloader --ignore-platform-reqs

# Install frontend modules and compile code blocks
RUN npm ci && npm run build

# ==============================================================================
# STAGE 2: High-Speed Production Application Environment
# ==============================================================================
FROM php:8.3-fpm-alpine

# Install core production services
RUN apk add --no-cache nginx supervisor bash postgresql-client mariadb-client

# Grab the official installer utility directly from its Docker Hub image
COPY --from=mlocati/php-extension-installer /usr/bin/install-php-extensions /usr/local/bin/

# Install all extensions dynamically without manually juggling header paths
RUN chmod +x /usr/local/bin/install-php-extensions && \
    install-php-extensions pdo_mysql pdo_pgsql gd zip bcmath opcache mbstring openssl tokenizer xml ctype json fileinfo curl

# Configure optimal production caching rules inside PHP
RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini" \
    && echo "opcache.enable_cli=1" >> "$PHP_INI_DIR/conf.d/docker-php-ext-opcache.ini" \
    && echo "upload_max_filesize=32M" >> "$PHP_INI_DIR/conf.d/uploads.ini" \
    && echo "post_max_size=32M" >> "$PHP_INI_DIR/conf.d/uploads.ini"

WORKDIR /var/www/html

# Transfer completed file assembly from builder layer
COPY --from=builder /app /var/www/html

# Inject absolute Nginx server configurations cleanly
RUN echo "server {" > /etc/nginx/http.d/default.conf \
    && echo "    listen 80 default_server;" >> /etc/nginx/http.d/default.conf \
    && echo "    root /var/www/html/public;" >> /etc/nginx/http.d/default.conf \
    && echo "    index index.php index.html;" >> /etc/nginx/http.d/default.conf \
    && echo "    charset utf-8;" >> /etc/nginx/http.d/default.conf \
    && echo "    location / {" >> /etc/nginx/http.d/default.conf \
    && echo "        try_files \$uri \$uri/ /index.php?\$query_string;" >> /etc/nginx/http.d/default.conf \
    && echo "    }" >> /etc/nginx/http.d/default.conf \
    && echo "    location ~ \.php$ {" >> /etc/nginx/http.d/default.conf \
    && echo "        fastcgi_pass 127.0.0.1:9000;" >> /etc/nginx/http.d/default.conf \
    && echo "        fastcgi_index index.php;" >> /etc/nginx/http.d/default.conf \
    && echo "        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;" >> /etc/nginx/http.d/default.conf \
    && echo "        include fastcgi_params;" >> /etc/nginx/http.d/default.conf \
    && echo "    }" >> /etc/nginx/http.d/default.conf \
    && echo "}" >> /etc/nginx/http.d/default.conf

# Inject Supervisor multi-process configuration parameters safely
RUN echo "[supervisord]" > /etc/supervisord.conf \
    && echo "nodaemon=true" >> /etc/supervisord.conf \
    && echo "user=root" >> /etc/supervisord.conf \
    && echo "[program:php-fpm]" >> /etc/supervisord.conf \
    && echo "command=php-fpm" >> /etc/supervisord.conf \
    && echo "stdout_logfile=/dev/stdout" >> /etc/supervisord.conf \
    && echo "stdout_logfile_maxbytes=0" >> /etc/supervisord.conf \
    && echo "stderr_logfile=/dev/stderr" >> /etc/supervisord.conf \
    && echo "stderr_logfile_maxbytes=0" >> /etc/supervisord.conf \
    && echo "[program:nginx]" >> /etc/supervisord.conf \
    && echo "command=nginx -g 'daemon off;'" >> /etc/supervisord.conf \
    && echo "stdout_logfile=/dev/stdout" >> /etc/supervisord.conf \
    && echo "stdout_logfile_maxbytes=0" >> /etc/supervisord.conf \
    && echo "stderr_logfile=/dev/stderr" >> /etc/supervisord.conf \
    && echo "stderr_logfile_maxbytes=0" >> /etc/supervisord.conf

# Write the shell execution file to manage system bootstrap routines cleanly
RUN echo "#!/bin/sh" > /usr/local/bin/entrypoint.sh \
    && echo "echo 'Enforcing fresh configuration files...'" >> /usr/local/bin/entrypoint.sh \
    && echo "cp /var/www/html/.env.example /var/www/html/.env" >> /usr/local/bin/entrypoint.sh \
    && echo "echo 'Wiping out stale setup configuration caches...'" >> /usr/local/bin/entrypoint.sh \
    && echo "php artisan config:clear" >> /usr/local/bin/entrypoint.sh \
    && echo "php artisan cache:clear" >> /usr/local/bin/entrypoint.sh \
    && echo "php artisan route:clear" >> /usr/local/bin/entrypoint.sh \
    && echo "php artisan view:clear" >> /usr/local/bin/entrypoint.sh \
    && echo "echo 'Applying runtime permissions...'" >> /usr/local/bin/entrypoint.sh \
    && echo "chown -R www-data:www-data /var/www/html" >> /usr/local/bin/entrypoint.sh \
    && echo "chmod -R 775 /var/www/html/storage /var/www/html/bootstrap/cache" >> /usr/local/bin/entrypoint.sh \
    && echo "chmod 664 /var/www/html/.env" >> /usr/local/bin/entrypoint.sh \
    && echo "echo 'Initializing application production encryption keys...'" >> /usr/local/bin/entrypoint.sh \
    && echo "php artisan key:generate --force" >> /usr/local/bin/entrypoint.sh \
    && echo "echo 'Running active structural database schema migrations...'" >> /usr/local/bin/entrypoint.sh \
    && echo "php artisan migrate:fresh --seed --force" >> /usr/local/bin/entrypoint.sh \
    && echo "echo 'Creating public storage folder links...'" >> /usr/local/bin/entrypoint.sh \
    && echo "php artisan storage:link --force" >> /usr/local/bin/entrypoint.sh \
    && echo "echo 'Launching process manager stack...'" >> /usr/local/bin/entrypoint.sh \
    && echo "exec /usr/bin/supervisord -c /etc/supervisord.conf" >> /usr/local/bin/entrypoint.sh \
    && chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 80
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
