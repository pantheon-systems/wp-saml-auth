<?php

class WP_SAML_Auth_Test_CLI extends WP_SAML_Auth_CLI {

	public static function scaffold_config_function( $assoc_args ) {
		return parent::scaffold_config_function( $assoc_args );
	}

}

tests_add_filter('plugins_loaded', function () {
	$root = dirname(__DIR__, 2);

	// Plugin CLI class (usually not autoloaded unless WP-CLI is present)
	$cli = $root . '/inc/class-wp-saml-auth-cli.php';
	if (is_file($cli)) { require_once $cli; }

	// Test helper class used by CLI tests
	$testCli = dirname(__DIR__) . '/phpunit/class-wp-saml-auth-test-cli.php';
	if (is_file($testCli)) { require_once $testCli; }
}, 1);
