<?php
// Define early to satisfy older configs, then hand off to the real bootstrap.
if (!defined('WP_PHP_BINARY')) {
	define('WP_PHP_BINARY', PHP_BINARY ?: 'php');
}
if (!defined('WP_RUN_CORE_TESTS')) {
	define('WP_RUN_CORE_TESTS', false);
}

require __DIR__ . '/bootstrap.php';
