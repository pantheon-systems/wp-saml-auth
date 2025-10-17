<?php
/**
 * Minimal PSR-4 autoloader for the SimpleSAMLphp stubs used in unit tests.
 */
spl_autoload_register( function ( $class ) {
    $prefix = 'SimpleSAML\\';
    if ( strpos( $class, $prefix ) !== 0 ) {
        return;
    }
    $relative = substr( $class, strlen( $prefix ) );           // e.g. "Auth\Simple"
    $path     = __DIR__ . '/SimpleSAML/' . str_replace('\\', '/', $relative) . '.php';
    if ( file_exists( $path ) ) {
        require $path;
    }
} );
