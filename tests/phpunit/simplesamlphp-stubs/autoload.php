<?php
/**
 * Minimal autoloader for SimpleSAMLphp stubs used in unit tests.
 */
spl_autoload_register(function ($class) {
    $prefix = 'SimpleSAML\\';
    $baseDir = __DIR__ . '/src/SimpleSAML/';

    $len = strlen($prefix);
    if (strncmp($prefix, $class, $len) !== 0) {
        return;
    }

    $relative = substr($class, $len);
    $file = $baseDir . str_replace('\\', '/', $relative) . '.php';
    if (is_file($file)) {
        require $file;
    }
});
