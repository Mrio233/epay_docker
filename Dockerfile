FROM php:8.0-fpm

# Install system dependencies and PHP extensions
RUN apt-get update && apt-get install -y --no-install-recommends \
    nginx \
    libfreetype6-dev \
    libjpeg62-turbo-dev \
    libpng-dev \
    libzip-dev \
    libonig-dev \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    unzip \
    git \
    cron \
    mariadb-client \
    curl \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) \
        pdo_mysql \
        mysqli \
        gd \
        zip \
        mbstring \
        bcmath \
        opcache \
        exif \
        fileinfo \
        xml \
        curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Ensure PHP-FPM listens on TCP 9000 for nginx in the same container
RUN sed -i 's|^listen = .*|listen = 127.0.0.1:9000|' /usr/local/etc/php-fpm.d/www.conf

# Install Composer
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# PHP production tuning
RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"
COPY docker/php/php.ini "$PHP_INI_DIR/conf.d/99-app.ini"

# Nginx config
COPY docker/nginx/default.conf /etc/nginx/conf.d/default.conf
RUN rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

# Project files
WORKDIR /var/www/html
COPY . /var/www/html

# Optimize autoloader (vendor is bundled in build context)
RUN cd /var/www/html/includes && \
    composer dump-autoload --optimize --no-interaction && \
    composer clear-cache

# Permissions: writable directories
RUN chown -R www-data:www-data /var/www/html && \
    chmod -R 755 /var/www/html && \
    chmod -R 775 /var/www/html/cache 2>/dev/null || true && \
    chmod -R 775 /var/www/html/plugins 2>/dev/null || true && \
    chmod -R 775 /var/www/html/assets 2>/dev/null || true && \
    chmod -R 775 /var/www/html/template 2>/dev/null || true

# Entrypoint script
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 80

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
