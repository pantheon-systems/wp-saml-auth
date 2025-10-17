<?php
/**
 * Minimal autoloader for our SimpleSAML stubs, used by the plugin under test.
 */
spl_autoload_register(function ($class) {
    $prefix = 'SimpleSAML\\';
    if (strncmp($class, $prefix, strlen($prefix)) !== 0) {
        return;
    }
    $relative = substr($class, strlen($prefix));
    $file = __DIR__ . '/SimpleSAML/' . str_replace('\\', '/', $relative) . '.php';
    if (is_file($file)) {
        require $file;
    }
});
