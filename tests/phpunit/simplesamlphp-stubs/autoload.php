<?php
/**
 * Minimal SimpleSAMLphp autoloader for the test suite.
 * The plugin calls require on this file via the 'simplesamlphp_autoload' option.
 */

$base = __DIR__;

// Load the legacy (underscore) class first.
require_once $base . '/class-simplesaml-auth-simple.php';

// Provide the namespaced class name as an alias so both styles work.
if (!class_exists('SimpleSAML\\Auth\\Simple', false) && class_exists('SimpleSAML_Auth_Simple', false)) {
    class_alias('SimpleSAML_Auth_Simple', 'SimpleSAML\\Auth\\Simple');
}

return true;
