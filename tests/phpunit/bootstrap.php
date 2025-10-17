<?php
/**
 * PHPUnit bootstrap file
 *
 * @package Wp_Saml_Auth
 */

$_tests_dir = getenv('WP_TESTS_DIR');
if (! $_tests_dir) {
    $_tests_dir = '/tmp/wordpress-tests-lib';
}

define('WP_TESTS_PHPUNIT_POLYFILLS_PATH', __DIR__ . '/../../vendor/yoast/phpunit-polyfills/phpunitpolyfills-autoload.php');

// Give access to tests_add_filter() function.
require_once $_tests_dir . '/includes/functions.php';

/**
 * Manually load the plugin being tested with the SAML stubs and sane defaults.
 */
function _manually_load_plugin() {
    $stub_autoload = __DIR__ . '/simplesamlphp-stubs/autoload.php';

    // Always use our SimpleSAML stub (new-style filter + legacy option).
    add_filter('wp_saml_auth_autoload', fn() => $stub_autoload);
    add_filter('wp_saml_auth_option', function ($value, $option) use ($stub_autoload) {
        if ($option === 'simplesamlphp_autoload') {
            return $stub_autoload;
        }
        return $value;
    }, 10, 2);

    // Provide default options the unit tests expect.
    // If a specific test wants to override, it can add its own filter in the test.
    add_filter('wp_saml_auth_option', function ($value, $option) {
        switch ($option) {
            case 'default_login':
                // Default to SAML (prevents plain login from taking over).
                return 'saml';
            case 'permit_wp_login':
                // Block username/password login by default (some tests assert false).
                return false;
            case 'auto_provision':
                // Allow auto-provisioning unless a test flips it off.
                return true;
            case 'user_login_attribute':
                return 'uid';
            case 'user_email_attribute':
                return 'mail';
            case 'user_first_name_attribute':
                return 'givenName';
            case 'user_last_name_attribute':
                return 'sn';
            default:
                return $value;
        }
    }, 9, 2);

    // Load plugin + test CLI helpers.
    require dirname(__DIR__, 3) . '/wp-saml-auth.php';
    require dirname(__DIR__, 3) . '/inc/class-wp-saml-auth-cli.php';
    require __DIR__ . '/class-wp-saml-auth-test-cli.php';
}
tests_add_filter('muplugins_loaded', '_manually_load_plugin');

// Keep your cookie/login shims.
function wp_set_auth_cookie($user_id, $remember = false, $secure = '', $token = '') {
    wp_set_current_user($user_id);
    return true;
}
function wp_logout() {
    wp_destroy_current_session();
    wp_set_current_user(0);
    do_action('wp_logout');
}

// Start up the WP testing environment.
require $_tests_dir . '/includes/bootstrap.php';
