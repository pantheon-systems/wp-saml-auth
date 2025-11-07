<?php
// Define early so WordPress tests are happy even if an old config is on disk.
if (!defined('WP_PHP_BINARY')) {
	define('WP_PHP_BINARY', PHP_BINARY ?: 'php');
}
if (!defined('WP_RUN_CORE_TESTS')) {
	define('WP_RUN_CORE_TESTS', false);
}

// Hand off to the real (self-provisioning) bootstrap.
require __DIR__ . '/bootstrap.php';
