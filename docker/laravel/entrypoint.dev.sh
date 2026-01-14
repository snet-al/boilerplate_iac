#!/bin/sh
set -e

echo "🚀 Starting Laravel Development Environment..."

# Wait for database
if [ -n "$DB_HOST" ]; then
    echo "⏳ Waiting for database..."
    while ! nc -z "$DB_HOST" "${DB_PORT:-3306}" 2>/dev/null; do
        sleep 1
    done
    echo "✅ Database is ready!"
fi

# Install dependencies if vendor doesn't exist
if [ ! -d "vendor" ]; then
    echo "📦 Installing Composer dependencies..."
    composer install
fi

# Generate app key if not set
if [ -z "$APP_KEY" ]; then
    echo "🔑 Generating application key..."
    php artisan key:generate
fi

# Run migrations
echo "🗃️ Running migrations..."
php artisan migrate --force || true

# Clear and cache config
echo "🧹 Clearing caches..."
php artisan config:clear
php artisan cache:clear
php artisan route:clear
php artisan view:clear

# Set permissions
chmod -R 775 storage bootstrap/cache 2>/dev/null || true

echo "✅ Laravel is ready!"

exec "$@"
