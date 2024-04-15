<?php

namespace App\Providers;

use Illuminate\Support\ServiceProvider;
use Inovector\Mixpost\Mixpost;
use Sentry\Laravel\Integration;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        Mixpost::report(function($exception) {
            Integration::captureUnhandledException($exception);
        });
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        //
    }
}
