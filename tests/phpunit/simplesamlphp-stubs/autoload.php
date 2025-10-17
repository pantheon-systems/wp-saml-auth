<?php
/**
 * Minimal PSR-4-ish autoloader for SimpleSAML classes used in tests.
 */
spl_autoload_register(function ($class) {
    // Only handle SimpleSAML classes.
    if (strpos($class, 'SimpleSAML\\') !== 0) {
        return;
    }

    $base = __DIR__ . '/src/';
    $relative = str_replace('\\', '/', $class) . '.php';
    $file = $base . $relative;

    if (file_exists($file)) {
        require $file;
    }
});
