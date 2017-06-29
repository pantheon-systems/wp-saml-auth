<?php

/**
 * Test all variations of authentication.
 */
class Test_Authentication extends WP_UnitTestCase {

	private $option = array();

	public function setUp() {
		parent::setUp();
		$this->options = array();
		$GLOBALS['wp_saml_auth_current_user'] = null;
		add_filter( 'wp_saml_auth_option', array( $this, 'filter_wp_saml_auth_option' ), 10, 2 );
	}

	public function test_default_behavior_saml_login_no_existing_user() {
		$this->assertEquals( 0, get_current_user_id() );
		$this->assertFalse( WP_SAML_Auth::get_instance()->get_provider()->isAuthenticated() );
		$this->assertFalse( get_user_by( 'login', 'student' ) );
		$this->saml_signon( 'student' );
		$user = wp_get_current_user();
		$this->assertEquals( 'student', $user->user_login );
		$this->assertEquals( 'student@example.org', $user->user_email );
		$this->assertEquals( array( 'subscriber' ), $user->roles );
		$this->assertEquals( $user, get_user_by( 'login', 'student' ) );
		wp_logout();
		$this->assertEquals( 0, get_current_user_id() );
		$this->assertFalse( WP_SAML_Auth::get_instance()->get_provider()->isAuthenticated() );
	}

	public function test_default_behavior_user_pass_login() {
		$this->factory->user->create( array( 'user_login' => 'testnowplogin', 'user_pass' => 'testnowplogin' ) );
		$this->assertFalse( WP_SAML_Auth::get_instance()->get_provider()->isAuthenticated() );
		$user = wp_signon( array(
			'user_login'     => 'testnowplogin',
			'user_password'  => 'testnowplogin',
		) );
		$this->assertInstanceOf( 'WP_User', $user );
		$user = wp_get_current_user();
		$this->assertEquals( 'testnowplogin', $user->user_login );
		$this->assertFalse( WP_SAML_Auth::get_instance()->get_provider()->isAuthenticated() );
		wp_logout();
		$this->assertEquals( 0, get_current_user_id() );
		$this->assertFalse( WP_SAML_Auth::get_instance()->get_provider()->isAuthenticated() );
	}

	public function test_saml_login_disable_auto_provision() {
		$this->options['auto_provision'] = false;
		// User doesn't exist yet, so expect an error
		$user = $this->saml_signon( 'student' );
		$this->assertTrue( WP_SAML_Auth::get_instance()->get_provider()->isAuthenticated() );
		$this->assertEquals( 0, get_current_user_id() );
		$this->assertInstanceOf( 'WP_Error', $user );
		$this->assertEquals( 'wp_saml_auth_auto_provision_disabled', $user->get_error_code() );
		// User exists now, so expect login to work with lookup by email address
		$user_id = $this->factory->user->create( array( 'user_login' => 'studentdifflogin', 'user_email' => 'student@example.org' ) );
		$user = $this->saml_signon( 'student' );
		$this->assertTrue( WP_SAML_Auth::get_instance()->get_provider()->isAuthenticated() );
		$this->assertInstanceOf( 'WP_User', $user );
		$this->assertEquals( 'studentdifflogin', $user->user_login );
		$this->assertEquals( 'studentdifflogin', wp_get_current_user()->user_login );
	}

	public function test_saml_login_disable_auto_provision_invalid_map_field() {
		$this->options['auto_provision'] = false;
		$this->options['get_user_by'] = 'login';
		$user_id = $this->factory->user->create( array( 'user_login' => 'studentdifflogin', 'user_email' => 'student@example.org' ) );
		$user = $this->saml_signon( 'student' );
		$this->assertTrue( WP_SAML_Auth::get_instance()->get_provider()->isAuthenticated() );
		$this->assertInstanceOf( 'WP_Error', $user );
		$this->assertEquals( 'wp_saml_auth_auto_provision_disabled', $user->get_error_code() );
	}

	public function test_saml_login_auto_provision_missing_field() {
		// Default behavior is to provision by email ddress
		$user = $this->saml_signon( 'studentwithoutmail' );
		$this->assertTrue( WP_SAML_Auth::get_instance()->get_provider()->isAuthenticated() );
		$this->assertEquals( 0, get_current_user_id() );
		$this->assertInstanceOf( 'WP_Error', $user );
		$this->assertEquals( 'wp_saml_auth_missing_attribute', $user->get_error_code() );
		// Changing field to 'login' will provision the user without an email address
		$this->options['get_user_by'] = 'login';
		$user = $this->saml_signon( 'studentwithoutmail' );
		$this->assertEquals( 'student', $user->user_login );
		$this->assertEmpty( $user->user_email );
		$this->assertEquals( 'student', wp_get_current_user()->user_login );
	}

	public function test_saml_login_auto_provision_custom_role() {
		$this->options['default_role'] = 'author';
		$user = $this->saml_signon( 'student' );
		$this->assertEquals( array( 'author' ), $user->roles );
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
		$_GET['action'] = 'wp-saml-auth';
		return wp_signon();
	}

	private function set_saml_auth_user( $username ) {
		$user = null;
		switch ( $username ) {
			case 'student':
			case 'studentwithoutuid':
			case 'studentwithoutmail':
				$user = array(
					'uid'                  => array( 'student' ),
					'eduPersonAffiliation' => array( 'member', 'student' ),
					'mail'                 => array( 'student@example.org' ),
				);
				if ( 'studentwithoutuid' === $username ) {
					unset( $user['uid'] );
				}
				if ( 'studentwithoutmail' === $username ) {
					unset( $user['mail'] );
				}
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
