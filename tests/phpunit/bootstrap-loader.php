<?php
// Define early so WordPress tests stop complaining even if wp-tests-config.php is old.
if (!defined('WP_PHP_BINARY')) {
	// Fallback to current PHP interpreter if PHP_BINARY is empty on some runners
	define('WP_PHP_BINARY', PHP_BINARY ?: 'php');
}
// Optional, harmless default
if (!defined('WP_RUN_CORE_TESTS')) {
	define('WP_RUN_CORE_TESTS', false);
}

// Now load your real bootstrap (the self-provisioning one you pasted)
require __DIR__ . '/bootstrap.php';
