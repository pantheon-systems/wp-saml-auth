<?php

/**
 * Test all variations of authentication.
 */
class Test_Authentication extends WP_UnitTestCase {

	private $option = array();

	public function setUp() {
		parent::setUp();
		$this->options = array();
		add_filter( 'wp_saml_auth_option', array( $this, 'filter_wp_saml_auth_option' ), 10, 2 );
	}

	public function test_user_pass_login_permitted() {
		$this->factory->user->create( array( 'user_login' => 'testnowplogin', 'user_pass' => 'testnowplogin' ) );
		$this->options['permit_wp_login'] = true;
		$user = wp_signon( array(
			'user_login'     => 'testnowplogin',
			'user_password'  => 'testnowplogin',
		) );
		$this->assertInstanceOf( 'WP_User', $user );
	}

	public function test_user_pass_login_not_permitted() {
		$this->factory->user->create( array( 'user_login' => 'testnowplogin', 'user_pass' => 'testnowplogin' ) );
		$this->options['permit_wp_login'] = false;
		$user = wp_signon( array(
			'user_login'     => 'testnowplogin',
			'user_password'  => 'testnowplogin',
		) );
		$this->assertInstanceOf( 'WP_Error', $user );
	}

	public function test_logout_calls_saml_logout() {
		$this->assertEquals( 0, get_current_user_id() );
		$this->assertFalse( WP_SAML_Auth::get_instance()->get_provider()->isAuthenticated() );
		$this->saml_signon( 'student' );
		$this->assertEquals( 'student@example.org', wp_get_current_user()->user_email );
		$this->assertTrue( WP_SAML_Auth::get_instance()->get_provider()->isAuthenticated() );
		wp_logout();
		$this->assertEquals( 0, get_current_user_id() );
		$this->assertFalse( WP_SAML_Auth::get_instance()->get_provider()->isAuthenticated() );
	}

	private function saml_signon( $username ) {
		$this->set_saml_auth_user( $username );
		$_GET['action'] = 'simplesamlphp';
		return wp_signon();
	}

	private function set_saml_auth_user( $username ) {
		$user = null;
		switch ( $username ) {
			case 'student':
				$user = array(
					'uid'                  => array( 'student' ),
					'eduPersonAffiliation' => array( 'member', 'student' ),
					'mail'                 => array( 'student@example.org' ),
				);
				break;
		}

		$GLOBALS['wp_saml_auth_current_user'] = $user;
	}

	public function filter_wp_saml_auth_option( $value, $option_name ) {
		if ( isset( $this->options[ $option_name ] ) ) {
			return $this->options[ $option_name ];
		}
		return $value;
	}

	public function tearDown() {
		remove_filter( 'wp_saml_auth_option', array( $this, 'filter_wp_saml_auth_option' ) );
		parent::tearDown();
	}

}
