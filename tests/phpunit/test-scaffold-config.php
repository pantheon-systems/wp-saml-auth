<?php

/**
 * Test all variations of scaffolding the config.
 */
class Test_Scaffold_Config extends WP_UnitTestCase {

	public function test_default_behavior() {

		$function = self::scaffold_config_function();
		$this->assertEquals( 'default-sp', $function( null, 'auth_source' ) );
		$this->assertEquals( true, $function( null, 'auto_provision' ) );
		$this->assertEquals( true, $function( null, 'permit_wp_login' ) );
		$this->assertEquals( 'email', $function( null, 'get_user_by' ) );
		$this->assertEquals( 'uid', $function( null, 'user_login_attribute' ) );
		$this->assertEquals( 'mail', $function( null, 'user_email_attribute' ) );
		$this->assertEquals( 'display_name', $function( null, 'display_name_attribute' ) );
		$this->assertEquals( 'first_name', $function( null, 'first_name_attribute' ) );
		$this->assertEquals( 'last_name', $function( null, 'last_name_attribute' ) );

	}

	public function test_false_auto_provision_permit_wp_login() {

		$function = self::scaffold_config_function( array(
			'permit_wp_login'   => 'false',
			'auto_provision'    => 'false',
		) );
		$this->assertEquals( false, $function( null, 'auto_provision' ) );
		$this->assertEquals( false, $function( null, 'permit_wp_login' ) );
	}

	/**
	 * Scaffolds a config function and evals it into scope
	 */
	private static function scaffold_config_function( $assoc_args = array() ) {
		$function_name = 'wpsax_' . md5( rand() );
		$function = WP_SAML_Auth_Test_CLI::scaffold_config_function( $assoc_args );
		$function = str_replace( 'function wpsax_filter_option', 'function ' . $function_name, $function );
		// @codingStandardsIgnoreStart
		eval( $function );
		return $function_name;
	}

}
