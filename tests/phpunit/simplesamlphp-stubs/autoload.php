<?php
spl_autoload_register(function ($class) {
    // Only one class is needed for these tests.
    if ($class === 'SimpleSAML\\Auth\\Simple' || $class === '\\SimpleSAML\\Auth\\Simple') {
        require __DIR__ . '/class-ssp-auth-simple.php';
    }
});
