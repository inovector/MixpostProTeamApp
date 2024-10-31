<?php

namespace App\Providers;

use Illuminate\Support\Facades\Broadcast;
use Inovector\Mixpost\Broadcast as MixpostBroadcast;
use Illuminate\Support\ServiceProvider;

class BroadcastServiceProvider extends ServiceProvider
{
    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        Broadcast::routes();

        MixpostBroadcast::routes();

        require base_path('routes/channels.php');
    }
}
