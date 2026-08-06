# ==============================================================================
# STAGE 1: Install PHP Dependencies & Build Frontend Assets
# ==============================================================================
FROM php:8.3-fpm-alpine AS builder

RUN apk add --no-cache --repository=http://alpinelinux.org \
    nodejs \
    npm \
    zip \
    libzip-dev \
    git \
    curl

WORKDIR /app
COPY . .

COPY --from=composer:2.7 /usr/bin/composer /usr/local/bin/composer
RUN composer install --no-interaction --prefer-dist --optimize-autoloader --ignore-platform-reqs
RUN npm ci && npm run build

# ==============================================================================
# STAGE 2: High-Speed Production Application Environment
# ==============================================================================
FROM php:8.3-fpm-alpine

RUN apk add --no-cache \
    nginx \
    supervisor \
    bash \
    postgresql-client \
    mariadb-client

RUN apk add --no-cache --repository=http://alpinelinux.org \
    php83-pdo_mysql \
    php83-pdo_pgsql \
    php83-gd \
    php83-zip \
    php83-bcmath \
    php83-opcache

RUN ln -sf /usr/lib/php83/modules/*.so /usr/local/lib/php/extensions/no-debug-non-zts-20230831/ \
    && echo "extension=pdo_mysql.so" > /usr/local/etc/php/conf.d/ext-pdo_mysql.ini \
    && echo "extension=pdo_pgsql.so" > /usr/local/etc/php/conf.d/ext-pdo_pgsql.ini \
    && echo "extension=gd.so" > /usr/local/etc/php/conf.d/ext-gd.ini \
    && echo "extension=zip.so" > /usr/local/etc/php/conf.d/ext-zip.ini \
    && echo "extension=bcmath.so" > /usr/local/etc/php/conf.d/ext-bcmath.ini \
    && echo "zend_extension=opcache.so" > /usr/local/etc/php/conf.d/ext-opcache.ini

RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini" \
    && echo "opcache.enable_cli=1" >> /usr/local/etc/php/conf.d/ext-opcache.ini \
    && echo "upload_max_filesize=32M" >> "$PHP_INI_DIR/conf.d/uploads.ini" \
    && echo "post_max_size=32M" >> "$PHP_INI_DIR/conf.d/uploads.ini"

WORKDIR /var/www/html
COPY --from=builder /app /var/www/html

RUN chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache \
    && chmod -R 775 /var/www/html/storage /var/www/html/bootstrap/cache

# Inject Nginx configurations safely
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

# Inject Supervisor configurations safely
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

# Inject the startup engine shell script with proper system formatting
RUN echo "#!/bin/sh" > /usr/local/bin/entrypoint.sh \
    && echo "echo 'Optimizing application run-caches...'" >> /usr/local/bin/entrypoint.sh \
    && echo "php artisan config:cache" >> /usr/local/bin/entrypoint.sh \
    && echo "php artisan route:cache" >> /usr/local/bin/entrypoint.sh \
    && echo "php artisan view:cache" >> /usr/local/bin/entrypoint.sh \
    && echo "echo 'Executing database migrations against Aiven...'" >> /usr/local/bin/entrypoint.sh \
    && echo "php artisan migrate --force" >> /usr/local/bin/entrypoint.sh \
    && echo "echo 'Enabling core framework modules...'" >> /usr/local/bin/entrypoint.sh \
    && echo "php artisan module:enable" >> /usr/local/bin/entrypoint.sh \
    && echo "echo 'Launching process manager stack...'" >> /usr/local/bin/entrypoint.sh \
    && echo "exec /usr/bin/supervisord -c /etc/supervisord.conf" >> /usr/local/bin/entrypoint.sh \
    && chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 80
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
