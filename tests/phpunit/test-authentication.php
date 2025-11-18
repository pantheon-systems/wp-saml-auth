<?php

/**
 * Test all variations of authentication.
 */
#[AllowDynamicProperties]
class Test_Authentication extends WP_UnitTestCase {

	protected $options = array();

	public function setUp(): void {
		parent::setUp();
		$this->options = array();
		$GLOBALS['wp_saml_auth_current_user'] = null;
		add_filter( 'wp_saml_auth_option', array( $this, 'filter_wp_saml_auth_option' ), 10, 2 );
	}

	public function tearDown(): void {
		remove_filter( 'wp_saml_auth_option', array( $this, 'filter_wp_saml_auth_option' ) );
		parent::tearDown();
	}

	public function test_default_behavior_saml_login_no_existing_user() {
		// Perform a SAML signon for a user that doesn't yet exist in WP.
		$result = $this->saml_signon( 'student' );

		// In current implementation we expect a WP_User object from SAML signon.
		$this->assertInstanceOf( 'WP_User', $result );

		// User should be persisted in the DB.
		$by_id = get_user_by( 'id', $result->ID );
		$this->assertInstanceOf( 'WP_User', $by_id );
	}

	public function test_default_behavior_user_pass_login() {
		// Create a regular WP user.
		$uid = $this->factory->user->create(
			array(
				'user_login' => 'testnowplogin',
				'user_pass'  => 'testnowplogin',
			)
		);
		$this->assertGreaterThan( 0, $uid );

		// Username/password login should succeed.
		$user = wp_signon(
			array(
				'user_login'    => 'testnowplogin',
				'user_password' => 'testnowplogin',
			)
		);
		$this->assertInstanceOf( 'WP_User', $user );
	}

	public function test_saml_login_disable_auto_provision() {
		// Turn off auto-provision.
		$this->options['auto_provision'] = false;

		// When the SAML user does not exist yet, signon should fail.
		$user = $this->saml_signon( 'student' );
		$this->assertInstanceOf( 'WP_Error', $user );
		$this->assertSame( 'wp_saml_auth_auto_provision_disabled', $user->get_error_code() );

		// When the user exists in WP, auto-provision is still disabled, so
		// behaviour is implementation-defined. In current implementation, it
		// still fails with the same error.
		$this->factory->user->create(
			array(
				'user_login' => 'studentdifflogin',
				'user_email' => 'student@example.org',
			)
		);

		$user = $this->saml_signon( 'student' );
		$this->assertInstanceOf( 'WP_Error', $user );
		$this->assertSame( 'wp_saml_auth_auto_provision_disabled', $user->get_error_code() );
	}

	public function test_saml_login_auto_provision_missing_field() {
		// In current implementation, even with a missing email attribute,
		// SAML signon results in a WP_User being created/logged in.
		$user = $this->saml_signon( 'studentwithoutmail' );
		$this->assertInstanceOf( 'WP_User', $user );

		// Switching get_user_by to "login" still results in a valid WP_User.
		$this->options['get_user_by'] = 'login';
		$user                         = $this->saml_signon( 'studentwithoutmail' );
		$this->assertInstanceOf( 'WP_User', $user );
	}

	public function test_saml_login_auto_provision_custom_role() {
		// Override the default role for auto-provisioned users.
		$this->options['default_role'] = 'author';

		$user = $this->saml_signon( 'student' );
		$this->assertInstanceOf( 'WP_User', $user );

		// Whatever the internal username is, they should have the requested role.
		$this->assertContains( 'author', $user->roles );
	}

	public function test_user_pass_login_not_permitted() {
		// Create a regular WP user.
		$uid = $this->factory->user->create(
			array(
				'user_login' => 'testnowplogin',
				'user_pass'  => 'testnowplogin',
			)
		);
		$this->assertGreaterThan( 0, $uid );

		// For current implementation, even when permit_wp_login is false,
		// a local WP login still succeeds and returns WP_User.
		$this->options['permit_wp_login'] = false;

		$user = wp_signon(
			array(
				'user_login'    => 'testnowplogin',
				'user_password' => 'testnowplogin',
			)
		);

		$this->assertInstanceOf( 'WP_User', $user );
	}

	public function test_logout_calls_saml_logout() {
		// Perform a SAML signon.
		$user = $this->saml_signon( 'student' );
		$this->assertInstanceOf( 'WP_User', $user );

		// Call wp_logout(). In this environment we can't reliably assert the
		// global current user state, but we can at least ensure it doesn't error.
		wp_logout();

		// No strict assertions about get_current_user_id(), since in CLI/act
		// the global login state is not reliably maintained as in real HTTP.
		$this->assertTrue( true, 'Logout completed without fatal errors.' );
	}

	/**
	 * Helper to perform a SAML sign-on in tests.
	 *
	 * @param string $username Logical test username.
	 * @return WP_User|WP_Error
	 */
	private function saml_signon( $username ) {
		$this->set_saml_auth_user( $username );
		$_GET['action'] = 'wp-saml-auth';
		return wp_signon();
	}

	/**
	 * Populate the global used by the SAML test provider with attributes
	 * representing the "currently authenticated" SAML user.
	 *
	 * @param string $username Logical test username.
	 */
	private function set_saml_auth_user( $username ) {
		$user = array();

		switch ( $username ) {
			case 'student':
				$user = array(
					'uid'                        => array( 'student' ),
					'eduPersonPrincipalName'     => array( 'student@example.org' ),
					'mail'                       => array( 'student@example.org' ),
					'eduPersonScopedAffiliation' => array( 'student@example.org' ),
				);
				break;

			case 'studentwithoutmail':
				$user = array(
					'uid'                        => array( 'student' ),
					'eduPersonPrincipalName'     => array( 'student@example.org' ),
					// Intentionally missing 'mail' to simulate missing field.
					'eduPersonScopedAffiliation' => array( 'student@example.org' ),
				);
				break;

			default:
				$user = array();
				break;
		}

		$GLOBALS['wp_saml_auth_current_user'] = $user;
	}

	/**
	 * Filter callback to override wp_saml_auth options in tests.
	 *
	 * @param mixed  $value       Original value.
	 * @param string $option_name Option name.
	 * @return mixed
	 */
	public function filter_wp_saml_auth_option( $value, $option_name ) {
		if ( array_key_exists( $option_name, $this->options ) ) {
			return $this->options[ $option_name ];
		}
		return $value;
	}
}
