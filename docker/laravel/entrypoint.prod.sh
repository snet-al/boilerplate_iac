#!/bin/sh
set -e

echo "🚀 Starting Laravel Production Environment..."

# Wait for database
if [ -n "$DB_HOST" ]; then
    echo "⏳ Waiting for database..."
    max_attempts=30
    attempt=1
    while ! nc -z "$DB_HOST" "${DB_PORT:-3306}" 2>/dev/null; do
        if [ $attempt -ge $max_attempts ]; then
            echo "❌ Database connection timeout"
            exit 1
        fi
        echo "Attempt $attempt/$max_attempts..."
        sleep 2
        attempt=$((attempt + 1))
    done
    echo "✅ Database is ready!"
fi

# Run migrations in production (with --force)
echo "🗃️ Running migrations..."
php artisan migrate --force

# Cache configuration for production
echo "⚡ Caching configuration..."
php artisan config:cache
php artisan route:cache
php artisan view:cache

# Set correct permissions
chown -R www-data:www-data storage bootstrap/cache
chmod -R 775 storage bootstrap/cache

echo "✅ Laravel Production is ready!"

exec "$@"
