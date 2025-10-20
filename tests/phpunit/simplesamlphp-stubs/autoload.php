<?php
/**
 * Autoloader for SimpleSAMLphp stubs used in PHPUnit.
 * - Loads the legacy global class SimpleSAML_Auth_Simple used by the plugin.
 * - Provides a minimal namespaced API by aliasing to the legacy class.
 */

// Ensure the global (legacy) stub class is available.
require_once __DIR__ . '/class-simplesaml-auth-simple.php';

// Alias legacy class to the namespaced one if needed.
if (! class_exists('SimpleSAML\\Auth\\Simple')) {
    class_alias('SimpleSAML_Auth_Simple', 'SimpleSAML\\Auth\\Simple');
}

// Minimal namespaced Configuration stub (some codepaths may touch it).
if (! class_exists('SimpleSAML\\Configuration')) {
    class SimpleSAML_Configuration {
        public static function getInstance() { return new self(); }
    }
}
