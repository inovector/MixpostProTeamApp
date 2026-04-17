#!/bin/bash

set -e

echo "Upgrade Mixpost Pro from v4 to v5"
echo ""

# Check composer is available
if ! command -v composer &> /dev/null; then
    echo "Error: composer is not installed or not in PATH."
    exit 1
fi

# Check we're in the right directory
if [ ! -f "composer.json" ]; then
    echo "Error: composer.json not found. Please run this script from the project root."
    exit 1
fi

# Check if already on Mixpost v5
CURRENT_VERSION=$(composer show inovector/mixpost-pro-team --format=json 2>/dev/null | php -r 'echo json_decode(file_get_contents("php://stdin"))->versions[0] ?? "";' 2>/dev/null)
if [[ "$CURRENT_VERSION" == 5.* ]]; then
    echo "Mixpost Pro is already on v5 ($CURRENT_VERSION). No upgrade needed."
    exit 0
fi

# Put application in maintenance mode
php artisan down --refresh=15 2>/dev/null || true

echo "Updating composer.json dependencies..."

# Update dependencies
composer require inovector/mixpost-pro-team:^5.0 laravel/framework:^13.0 laravel/tinker:^3.0 --no-update

# Remove unused dev dependencies
composer remove fakerphp/faker mockery/mockery phpunit/phpunit spatie/laravel-ignition --dev --no-update 2>/dev/null || true

# Update collision to support Laravel 13
composer require nunomaduro/collision:"^8.1|^9.0" --dev --no-update

echo ""
echo "Running composer update..."
composer update

echo ""
echo "Publishing assets..."
php artisan mixpost:publish-assets --force=true

echo ""
echo "Creating upgrade migration..."
MIGRATION_SOURCE="vendor/inovector/mixpost-pro-team/database/migrations-upgrade/2026_04_01_123148_upgrade_mixpost_v5.php"
MIGRATION_DEST="database/migrations/2026_04_01_123148_upgrade_mixpost_v5.php"

if [ ! -f "$MIGRATION_SOURCE" ]; then
    echo "Error: Migration file not found at $MIGRATION_SOURCE"
    php artisan up
    exit 1
fi

cp "$MIGRATION_SOURCE" "$MIGRATION_DEST"
echo "Migration copied to $MIGRATION_DEST"

echo ""
echo "Running migrations..."
php artisan migrate --force

echo ""
echo "Updating Horizon configuration..."
HORIZON_CONFIG_URL="https://raw.githubusercontent.com/inovector/MixpostProTeamApp/main/config/horizon.php"
if curl -fsSL "$HORIZON_CONFIG_URL" -o config/horizon.php; then
    echo "Horizon configuration updated."
else
    echo "Warning: Failed to download horizon.php from $HORIZON_CONFIG_URL, skipping Horizon configuration."
fi

echo ""
echo "Publishing config..."
php artisan vendor:publish --tag=mixpost-config --force

echo ""
echo "Clearing caches..."
php artisan route:clear
php artisan view:clear
php artisan mixpost:clear-services-cache
php artisan mixpost:clear-settings-cache

echo ""
echo "Optimizing application..."
php artisan optimize

echo ""
echo "Restarting Reverb..."
php artisan reverb:restart 2>/dev/null || true

echo ""
echo "Terminating Horizon..."
php artisan horizon:terminate 2>/dev/null || true

# Bring application back up
php artisan up

echo ""
echo "Mixpost Pro has been upgraded to v5 successfully!"
