<?php
/**
 * PHPUnit bootstrap file for wp-saml-auth.
 * Keeps prior logic but ensures WP_UnitTestCase is available by loading WP tests bootstrap
 * and that a valid bootstrap path is always used.
 */

$_tests_dir = getenv('WP_TESTS_DIR') ?: '/tmp/wordpress-tests-lib';

/** Load Yoast Polyfills early */
$poly = getenv('WP_TESTS_PHPUNIT_POLYFILLS_PATH');
if ($poly && is_file($poly . '/vendor/autoload.php')) {
    require_once $poly . '/vendor/autoload.php';
} else {
    $fallback = dirname(__DIR__, 2) . '/vendor/yoast/phpunit-polyfills/phpunitpolyfills-autoload.php';
    if (is_file($fallback)) {
        require_once $fallback;
    }
}

/** tests_add_filter */
require_once $_tests_dir . '/includes/functions.php';

/** Manually load the plugin and CLI classes (same as before) */
function _manually_load_plugin() {
    $root = dirname(__DIR__, 2);
    foreach (['/wp-saml-auth.php','/plugin.php','/index.php'] as $rel) {
        $p = $root . $rel;
        if (file_exists($p)) { require $p; break; }
    }
    $cli_main = $root . '/inc/class-wp-saml-auth-cli.php';
    if (file_exists($cli_main)) { require $cli_main; }
    $cli_test = __DIR__ . '/class-wp-saml-auth-test-cli.php';
    if (file_exists($cli_test)) { require $cli_test; }

    add_filter( 'wp_saml_auth_option', '_wp_saml_auth_filter_option', 10, 2 );
}
tests_add_filter('muplugins_loaded', '_manually_load_plugin');

/** Option defaults as before */
function _wp_saml_auth_filter_option( $value, $name ) {
    if ($name === 'simplesamlphp_autoload') {
        $autoload = getenv('SIMPLESAMLPHP_AUTOLOAD');
        if ($autoload && file_exists($autoload)) return $autoload;
        return '/tmp/simplesamlphp-stub/autoload.php';
    }
    if ($name === 'auto_provision') return true;
    if ($name === 'permit_wp_login') return true;
    if ($name === 'default_role') return 'subscriber';
    return $value;
}

/** wp_logout shim if required */
if (!function_exists('wp_logout')) {
    function wp_logout() {
        if (function_exists('wp_destroy_current_session')) wp_destroy_current_session();
        if (function_exists('wp_set_current_user')) wp_set_current_user(0);
        do_action('wp_logout');
    }
}

/** Finally load WP tests bootstrap (defines WP_UnitTestCase) */
require $_tests_dir . '/includes/bootstrap.php';
