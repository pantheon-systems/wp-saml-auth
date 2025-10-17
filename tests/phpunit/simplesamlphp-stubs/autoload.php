<?php
spl_autoload_register(function ($class) {
    if ($class === 'SimpleSAML\\Auth\\Simple' || $class === '\\SimpleSAML\\Auth\\Simple') {
        require __DIR__ . '/class-ssp-auth-simple.php';
    }
});
