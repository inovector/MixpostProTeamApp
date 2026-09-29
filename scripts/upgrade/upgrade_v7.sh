#!/bin/bash

set -e

echo "Upgrade Mixpost Pro from v6 to v7"
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

# Check if already on Mixpost v7
CURRENT_VERSION=$(composer show inovector/mixpost-pro-team --format=json 2>/dev/null | php -r 'echo json_decode(file_get_contents("php://stdin"))->versions[0] ?? "";' 2>/dev/null)
if [[ "$CURRENT_VERSION" == 7.* ]]; then
    echo "Mixpost Pro is already on v7 ($CURRENT_VERSION). No upgrade needed."
    exit 0
fi

# Put application in maintenance mode
php artisan down --refresh=15 2>/dev/null || true

echo "Updating composer.json dependencies..."

# Update dependencies
composer require inovector/mixpost-pro-team:^7.0 -W

echo ""
echo "Running composer update..."
composer update

echo ""
echo "Publishing assets..."
php artisan mixpost:publish-assets --force=true

echo ""
echo "Running upgrade migrations..."
php artisan mixpost:upgrade-database --force

echo ""
echo "Publishing config..."
php artisan vendor:publish --tag=mixpost-config --force

# v7 changes the MIXPOST_CORE_PATH default from `mixpost` to empty, which would move
# the dashboard and every social provider callback URL to the root of the domain.
# Pin the previous value so this upgrade does not change any URL on its own.
echo ""
echo "Checking MIXPOST_CORE_PATH..."
if [ -f ".env" ]; then
    if grep -q "^MIXPOST_CORE_PATH=" .env; then
        echo "MIXPOST_CORE_PATH is already set in .env, leaving it untouched."
    else
        printf '\n# v7 changed the default to empty, which serves Mixpost from the root of the domain.\n# Pinned to `mixpost` so this installation keeps the URLs it already used.\nMIXPOST_CORE_PATH=mixpost\n' >> .env
        echo "Pinned MIXPOST_CORE_PATH=mixpost in .env to preserve your current URLs."
        echo "To serve Mixpost from the root instead, set it empty and update the Redirect URIs"
        echo "in your social provider apps - see https://docs.mixpost.app/pro/upgrading/upgrading-v7"
    fi
else
    echo "Warning: .env not found, skipping. Mixpost is served from the root unless MIXPOST_CORE_PATH is set."
fi

# Horizon's longest supervisor timeout is 900s, so the queue connection needs retry_after >= 960.
# Below that, Redis hands a still-running job to a second worker and the post publishes twice.
echo ""
echo "Checking the mixpost-redis retry_after..."
if [ -f "config/queue.php" ]; then
    php -r '
        $file = "config/queue.php";
        $contents = file_get_contents($file);
        if (strpos($contents, "\x27retry_after\x27 => 960,") !== false) {
            echo "retry_after is already 960.\n";
            exit(0);
        }
        if (strpos($contents, "\x27retry_after\x27 => 11 * 60,") === false) {
            echo "Warning: could not find the expected retry_after value, skipping.\n";
            echo "         Set retry_after to at least 960 on the mixpost-redis connection,\n";
            echo "         otherwise long jobs can be picked up twice.\n";
            exit(0);
        }
        file_put_contents($file, str_replace("\x27retry_after\x27 => 11 * 60,", "\x27retry_after\x27 => 960,", $contents));
        echo "retry_after raised to 960 on the mixpost-redis connection.\n";
    '
else
    echo "Warning: config/queue.php not found, skipping."
fi

# The root redirect only makes sense while Mixpost runs behind a prefix. With an empty
# core path Mixpost owns `/` itself, and this route would shadow it.
echo ""
echo "Adapting routes/web.php..."
if [ -f "routes/web.php" ]; then
    php -r '
        $file = "routes/web.php";
        $import = "use Inovector\\Mixpost\\Util;";
        $anchor = "use Illuminate\\Support\\Facades\\Route;";
        $old = "Route::get(\x27/\x27, function () {\n    return redirect()->to(config(\x27mixpost.core_path\x27));\n});";
        $new = "// Only send the domain root to Mixpost when it runs behind a path prefix.\n// With an empty core path Mixpost already owns `/`, and these routes are\n// registered after the package\x27s, so a route here would shadow it.\nif (\$corePath = Util::corePath()) {\n    Route::get(\x27/\x27, function () use (\$corePath) {\n        return redirect()->to(\$corePath);\n    });\n}";
        $contents = file_get_contents($file);
        if (strpos($contents, "Util::corePath()") !== false) {
            echo "routes/web.php is already up to date.\n";
            exit(0);
        }
        if (strpos($contents, $old) === false) {
            echo "Warning: routes/web.php has been customized, skipping.\n";
            echo "         If it registers a route on `/`, it will shadow the Mixpost dashboard\n";
            echo "         when MIXPOST_CORE_PATH is empty.\n";
            exit(0);
        }
        $contents = str_replace($old, $new, $contents);
        if (strpos($contents, $import) === false) {
            $contents = strpos($contents, $anchor) !== false
                ? str_replace($anchor, $anchor . "\n" . $import, $contents)
                : preg_replace("/^<\\?php\n/", "<?php\n\n" . $import . "\n", $contents, 1);
        }
        file_put_contents($file, $contents);
        echo "routes/web.php updated.\n";
    '
else
    echo "Warning: routes/web.php not found, skipping."
fi

echo ""
echo "Clearing caches..."
php artisan optimize:clear --except cache
php artisan mixpost:clear-services-cache
php artisan mixpost:clear-settings-cache

echo ""
echo "Optimizing application..."
php artisan optimize --except cache

echo ""
echo "Restarting Reverb..."
php artisan reverb:restart 2>/dev/null || true

echo ""
echo "Terminating Horizon..."
php artisan horizon:terminate 2>/dev/null || true

# Bring application back up
php artisan up

echo ""
echo "Mixpost Pro has been upgraded to v7 successfully!"
