#!/bin/bash
set -e

# Wait for MySQL to be ready
wait_for_mysql() {
    local host="${DB_HOST:-mysql}"
    local port="${DB_PORT:-3306}"
    local user="${DB_USER:-root}"
    local pass="${DB_PASSWORD:-}"
    local max_attempts=30
    local attempt=0

    echo "Waiting for MySQL at ${host}:${port}..."
    while [ $attempt -lt $max_attempts ]; do
        if mysqladmin ping -h"$host" -P"$port" -u"$user" ${pass:+-p"$pass"} --silent 2>/dev/null; then
            echo "MySQL is ready!"
            return 0
        fi
        attempt=$((attempt + 1))
        echo "MySQL not ready, attempt $attempt/$max_attempts..."
        sleep 2
    done

    echo "MySQL did not become ready in time."
    return 1
}

# Auto-import SQL if database is empty
init_database() {
    local host="${DB_HOST:-mysql}"
    local port="${DB_PORT:-3306}"
    local user="${DB_USER:-root}"
    local pass="${DB_PASSWORD:-}"
    local dbname="${DB_NAME:-epay}"
    local dbqz="${DB_PREFIX:-pay}"
    local sql_file="/var/www/html/install/install.sql"

    if [ ! -f "$sql_file" ]; then
        echo "Install SQL not found at $sql_file, skipping DB init."
        return 0
    fi

    # Check if a known table exists (using configured prefix)
    local table_exists
    table_exists=$(mysql -h"$host" -P"$port" -u"$user" ${pass:+-p"$pass"} -D"$dbname" -e "SHOW TABLES LIKE '${dbqz}_order';" 2>/dev/null | grep -c "${dbqz}_order" || true)

    if [ "$table_exists" -eq 0 ]; then
        echo "Database appears empty. Initializing from install.sql..."
        # Replace `pre_` prefix in SQL with configured prefix before importing
        sed "s/\`pre_/\`${dbqz}_/g" "$sql_file" | mysql --default-character-set=utf8mb4 -h"$host" -P"$port" -u"$user" ${pass:+-p"$pass"} -D"$dbname"
        echo "Database initialized."
    else
        echo "Database already initialized."
    fi

    # Prevent the web installer from being exposed
    mkdir -p /var/www/html/install
    touch /var/www/html/install/install.lock
}

# Ensure runtime directories are writable
fix_permissions() {
    local dirs="/var/www/html/cache /var/www/html/plugins /var/www/html/assets /var/www/html/template /var/www/html/user /var/www/html/admin /tmp"
    for d in $dirs; do
        if [ -d "$d" ]; then
            chown -R www-data:www-data "$d" 2>/dev/null || true
            chmod -R 775 "$d" 2>/dev/null || true
        fi
    done
    # Ensure session path is writable
    chown -R www-data:www-data /tmp
}

# Write config.php from environment if not exists or force update
write_config() {
    local config_file="/var/www/html/config.php"
    local host="${DB_HOST:-mysql}"
    local port="${DB_PORT:-3306}"
    local user="${DB_USER:-root}"
    local pass="${DB_PASSWORD:-}"
    local dbname="${DB_NAME:-epay}"
    local dbqz="${DB_PREFIX:-pay}"

    cat > "$config_file" <<EOF
<?php
/*数据库配置*/
\$dbconfig=array(
    'host' => '${host}',
    'port' => ${port},
    'user' => '${user}',
    'pwd'  => '${pass}',
    'dbname' => '${dbname}',
    'dbqz' => '${dbqz}'
);
EOF

    chown www-data:www-data "$config_file"
    chmod 644 "$config_file"
    echo "config.php updated."
}

# Main
wait_for_mysql
write_config
init_database
fix_permissions

# Start PHP-FPM in background
php-fpm -D

# Execute the CMD (default: nginx -g 'daemon off;')
exec "$@"
