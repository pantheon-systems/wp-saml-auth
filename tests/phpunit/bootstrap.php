<?php
/**
 * PHPUnit bootstrap file
 *
 * @package Wp_Saml_Auth
 */

$_tests_dir = getenv( 'WP_TESTS_DIR' );
if ( ! $_tests_dir ) {
	$_tests_dir = '/tmp/wordpress-tests-lib';
}

define( 'WP_TESTS_PHPUNIT_POLYFILLS_PATH', __DIR__ . '/../../vendor/yoast/phpunit-polyfills/phpunitpolyfills-autoload.php' );

// --- Force-load the SimpleSAMLphp stubs early --------------------------------
$__stub_autoload = __DIR__ . '/simplesamlphp-stubs/autoload.php';
if ( ! file_exists( $__stub_autoload ) ) {
	// Fallback for older test layout.
	$__stub_autoload = __DIR__ . '/class-simplesaml-auth-simple.php';
}
if ( file_exists( $__stub_autoload ) ) {
	define( 'WP_SAML_AUTH_AUTOLOAD', $__stub_autoload );
	putenv( 'WP_SAML_AUTH_AUTOLOAD=' . $__stub_autoload );
	require_once $__stub_autoload;
} else {
	fwrite( STDERR, "SimpleSAMLphp test stubs not found at expected path.\n" );
}

// Give access to tests_add_filter() function.
require_once $_tests_dir . '/includes/functions.php';

/**
 * Manually load the plugin being tested.
 */
function _manually_load_plugin() {
	$root = dirname( dirname( dirname( __FILE__ ) ) ); // repo root

	require $root . '/wp-saml-auth.php';
	require $root . '/inc/class-wp-saml-auth-cli.php';
	require __DIR__ . '/class-wp-saml-auth-test-cli.php';

	// Provide legacy option path for older code paths.
	add_filter( 'wp_saml_auth_option', '_wp_saml_auth_filter_option', 10, 2 );
}
tests_add_filter( 'muplugins_loaded', '_manually_load_plugin' );

/**
 * Default plugin options for tests (can be overridden per-test).
 */
function _wp_saml_auth_filter_option( $value, $option_name ) {
	switch ( $option_name ) {
		case 'simplesamlphp_autoload':
			$value = defined( 'WP_SAML_AUTH_AUTOLOAD' ) ? WP_SAML_AUTH_AUTOLOAD : $value;
			break;

		// Disallow username/password logins by default in unit tests.
		case 'permit_wp_login':
		case 'permit_user_login':
			$value = false;
			break;

		// Allow auto-provisioning by default so tests can create users when attributes are present.
		case 'auto_provision':
			$value = true;
			break;

		// Attribute map defaults align with our stub attributes.
		case 'user_login_attribute':
			$value = 'uid';
			break;
		case 'user_email_attribute':
			$value = 'mail';
			break;
		case 'user_role_attribute':
			$value = 'eduPersonAffiliation';
			break;

		// Reasonable defaults.
		case 'default_role':
			$value = 'subscriber';
			break;
	}
	return $value;
}

// Start up the WP testing environment.
require $_tests_dir . '/includes/bootstrap.php';

// Newer code path: allow forcing the autoloader via filter after WP boots.
add_filter( 'wp_saml_auth_autoload', function () {
	return defined( 'WP_SAML_AUTH_AUTOLOAD' ) ? WP_SAML_AUTH_AUTOLOAD : null;
} );

/**
 * In tests we don't want cookies/network effects; return false to match assertions.
 */
if ( ! function_exists( 'wp_set_auth_cookie' ) ) {
	function wp_set_auth_cookie( $user_id, $remember = false, $secure = '', $token = '' ) {
		wp_set_current_user( $user_id );
		return false;
	}
}

/**
 * Tests assert a "falsey" return on logout; also fire the standard hook.
 */
if ( ! function_exists( 'wp_logout' ) ) {
	function wp_logout() {
		wp_destroy_current_session();
		wp_set_current_user( 0 );
		do_action( 'wp_logout' );
		return false;
	}
}
