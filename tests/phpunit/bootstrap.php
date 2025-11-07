<?php
/**
 * PHPUnit bootstrap file for wp-saml-auth
 *
 * Preserves prior logic:
 * - Uses WP core tests at WP_TESTS_DIR (default /tmp/wordpress-tests-lib)
 * - Loads Yoast PHPUnit Polyfills (preferring env WP_TESTS_PHPUNIT_POLYFILLS_PATH, falling back to repo vendor)
 * - Manually loads plugin main file and CLI classes
 * - Adds option filters for SAML settings if needed
 * - Provides wp_logout() shim for older cores when required
 */

$_tests_dir = getenv('WP_TESTS_DIR');
if (! $_tests_dir) {
	$_tests_dir = '/tmp/wordpress-tests-lib';
}

/**
 * Load PHPUnit Polyfills early.
 * Prefer env-provided vendor tree (e.g. /tmp/phpunit-deps/vendor/autoload.php)
 * Fallback to the plugin vendor path you used before.
 */
$polyfills_env = getenv('WP_TESTS_PHPUNIT_POLYFILLS_PATH');
if ($polyfills_env && is_file($polyfills_env . '/vendor/autoload.php')) {
	require_once $polyfills_env . '/vendor/autoload.php';
} else {
	// previous in-repo path
	$repoPolyAutoload = dirname(__DIR__, 2) . '/vendor/yoast/phpunit-polyfills/phpunitpolyfills-autoload.php';
	if (is_file($repoPolyAutoload)) {
		require_once $repoPolyAutoload;
	}
}

// Give access to tests_add_filter() function.
require_once $_tests_dir . '/includes/functions.php';

/**
 * Manually load the plugin being tested and its CLI bits (as before).
 */
function _manually_load_plugin() {
	$root = dirname(__DIR__, 2);

	// Main plugin entry
	$candidates = [
		$root . '/wp-saml-auth.php',
		$root . '/plugin.php',
		$root . '/index.php',
	];
	foreach ($candidates as $file) {
		if (file_exists($file)) {
			require $file;
			break;
		}
	}

	// CLI classes used by tests (keep your previous behavior)
	$cli_main = $root . '/inc/class-wp-saml-auth-cli.php';
	if (file_exists($cli_main)) {
		require $cli_main;
	}
	$cli_test = __DIR__ . '/class-wp-saml-auth-test-cli.php';
	if (file_exists($cli_test)) {
		require $cli_test;
	}

	// Keep your option filter hook
	add_filter( 'wp_saml_auth_option', '_wp_saml_auth_filter_option', 10, 2 );
}
tests_add_filter('muplugins_loaded', '_manually_load_plugin');

/**
 * Preserve previous behavior: set defaults / stubs for specific options.
 */
function _wp_saml_auth_filter_option( $value, $option_name ) {
	switch ( $option_name ) {
		case 'simplesamlphp_autoload':
			// Either use env-provided autoload or a harmless stub path.
			$autoload = getenv('SIMPLESAMLPHP_AUTOLOAD');
			if ($autoload && file_exists($autoload)) {
				return $autoload;
			}
			return '/tmp/simplesamlphp-stub/autoload.php';

		case 'auto_provision':
			return true;

		case 'permit_wp_login':
			return true;

		case 'default_role':
			return 'subscriber';

		default:
			return $value;
	}
}

/**
 * Provide wp_logout shim if not defined (keeps older tests green).
 */
if ( ! function_exists( 'wp_logout' ) ) {
	function wp_logout() {
		if ( function_exists( 'wp_destroy_current_session' ) ) {
			wp_destroy_current_session();
		}
		if ( function_exists( 'wp_set_current_user' ) ) {
			wp_set_current_user( 0 );
		}
		do_action( 'wp_logout' );
	}
}

// Finally boot the WP test environment.
require $_tests_dir . '/includes/bootstrap.php';
