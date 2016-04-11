<?php

/**
 * Test all variations of authentication.
 */
class Test_Authentication extends WP_UnitTestCase {

	private $override = array();

	public function setUp() {
		parent::setUp();
		add_filter( 'wp_saml_auth_option', array( $this, 'filter_wp_saml_auth_option' ), 10, 2 );
	}

	public function test_user_pass_login_permitted() {
		$this->factory->user->create( array( 'user_login' => 'testnowplogin', 'user_pass' => 'testnowplogin' ) );
		$this->override['permit_wp_login'] = true;
		$user = wp_signon( array(
			'user_login'     => 'testnowplogin',
			'user_password'  => 'testnowplogin',
		) );
		$this->assertInstanceOf( 'WP_User', $user );
	}

	public function test_user_pass_login_not_permitted() {
		$this->factory->user->create( array( 'user_login' => 'testnowplogin', 'user_pass' => 'testnowplogin' ) );
		$this->override['permit_wp_login'] = false;
		$user = wp_signon( array(
			'user_login'     => 'testnowplogin',
			'user_password'  => 'testnowplogin',
		) );
		$this->assertInstanceOf( 'WP_Error', $user );
	}

	public function filter_wp_saml_auth_option( $value, $option_name ) {
		if ( isset( $this->override[ $option_name ] ) ) {
			return $this->override[ $option_name ];
		}
		return $value;
	}

	public function tearDown() {
		$this->override = array();
		remove_filter( 'wp_saml_auth_option', array( $this, 'filter_wp_saml_auth_option' ) );
		parent::tearDown();
	}

}
