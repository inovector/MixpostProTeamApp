<?php

use Illuminate\Support\Facades\Route;
use Inovector\Mixpost\Util;

/*
|--------------------------------------------------------------------------
| Web Routes
|--------------------------------------------------------------------------
|
| Here is where you can register web routes for your application. These
| routes are loaded by the RouteServiceProvider and all of them will
| be assigned to the "web" middleware group. Make something great!
|
*/

// Only send the domain root to Mixpost when it runs behind a path prefix.
// With an empty core path Mixpost already owns `/`, and these routes are
// registered after the package's, so a route here would shadow it.
if ($corePath = Util::corePath()) {
    Route::get('/', function () use ($corePath) {
        return redirect()->to($corePath);
    });
}
