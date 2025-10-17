<?php
/**
 * PHPUnit bootstrap file
 *
 * @package Wp_Saml_Auth
 */

// WP test lib location (provided by the workflow via WP_TESTS_DIR)
$_tests_dir = getenv( 'WP_TESTS_DIR' );
if ( ! $_tests_dir ) {
	$_tests_dir = '/tmp/wordpress-tests-lib';
}

// Yoast polyfills path for cross-PHP PHPUnit features
define(
	'WP_TESTS_PHPUNIT_POLYFILLS_PATH',
	__DIR__ . '/../../vendor/yoast/phpunit-polyfills/phpunitpolyfills-autoload.php'
);

// Give access to tests_add_filter()
require_once $_tests_dir . '/includes/functions.php';

/**
 * Manually load the plugin being tested.
 * IMPORTANT: load the SimpleSAML **stubs** before the plugin so set_provider()
 * sees a working autoloader and never touches real SimpleSAMLphp.
 */
function _manually_load_plugin() {
	// Resolve all paths relative to this file to avoid globals & CI cwd quirks.
	$root           = dirname( __DIR__, 2 ); // repo root (…/wp-saml-auth)
	$stubs_autoload = __DIR__ . '/simplesamlphp-stubs/autoload.php';
	$legacy_shim    = __DIR__ . '/class-simplesaml-auth-simple.php';

	// 1) Hard-require the stubs so classes exist even if options/filters aren’t read yet.
	if ( is_string( $stubs_autoload ) && $stubs_autoload !== '' && file_exists( $stubs_autoload ) ) {
		require_once $stubs_autoload;
	}

	// 2) Make both configuration paths point at our stubs.
	add_filter( 'wp_saml_auth_autoload', function () use ( $stubs_autoload ) {
		return $stubs_autoload;
	}, 1 );

	add_filter( 'wp_saml_auth_option', function( $value, $option_name ) use ( $stubs_autoload, $legacy_shim ) {
		if ( 'simplesamlphp_autoload' === $option_name ) {
			// Prefer stubs, fall back to the legacy shim (kept for older tests).
			return ( is_string( $stubs_autoload ) && file_exists( $stubs_autoload ) )
				? $stubs_autoload
				: $legacy_shim;
		}
		return $value;
	}, 1, 2 );

	// 3) Load the plugin and its CLI test harness from the repo root.
	require $root . '/wp-saml-auth.php';
	require $root . '/inc/class-wp-saml-auth-cli.php';
	require __DIR__ . '/class-wp-saml-auth-test-cli.php';
}
tests_add_filter( 'muplugins_loaded', '_manually_load_plugin' );

/**
 * Minimal auth shims so unit tests don't fight cookies/sessions.
 */
function wp_set_auth_cookie( $user_id, $remember = false, $secure = '', $token = '' ) {
	wp_set_current_user( $user_id );
	return true;
}

function wp_logout() {
	wp_destroy_current_session();
	wp_set_current_user( 0 );
	do_action( 'wp_logout' );
}

// Boot the WP testing environment.
require $_tests_dir . '/includes/bootstrap.php';
