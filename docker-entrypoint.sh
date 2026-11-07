#!/bin/sh
set -e

cd /app

# A bind-mounted storage/ volume can shadow the directories created at build
# time, so make sure they exist and are writable on every boot.
mkdir -p \
    bootstrap/cache \
    storage/app/public \
    storage/framework/cache \
    storage/framework/sessions \
    storage/framework/views \
    storage/logs

chown -R www-data:www-data storage bootstrap/cache 2>/dev/null || true
chmod -R ug+rwX storage bootstrap/cache 2>/dev/null || true

if [ -z "${APP_KEY:-}" ]; then
    echo "WARNING: APP_KEY is not set. Run: php artisan key:generate" >&2
fi

# Public storage symlink (idempotent).
php artisan storage:link --no-interaction >/dev/null 2>&1 || true

if [ "${APP_OPTIMIZE:-false}" = "true" ]; then
    php artisan config:cache --no-interaction
    php artisan view:cache --no-interaction
fi

if [ "${RUN_MIGRATIONS:-false}" = "true" ]; then
    attempt=1

    # The database container's socket can accept connections before its TCP
    # port is up, so retry instead of aborting the boot.
    until php artisan migrate --force --no-interaction; do
        if [ "$attempt" -ge 30 ]; then
            echo "ERROR: database not reachable after ${attempt} attempts" >&2
            exit 1
        fi

        echo "Waiting for database (attempt ${attempt})..."
        attempt=$((attempt + 1))
        sleep 2
    done
fi

exec "$@"
