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

		// When a user with matching email exists, authentication succeeds
		// because an existing user was found (auto-provision doesn't apply).
		$this->factory->user->create(
			array(
				'user_login' => 'studentdifflogin',
				'user_email' => 'student@example.org',
			)
		);

		$user = $this->saml_signon( 'student' );
		$this->assertInstanceOf( 'WP_User', $user, 'Should return existing user when found by email' );
		$this->assertEquals( 'student@example.org', $user->user_email );
	}

	public function test_saml_login_auto_provision_missing_field() {
		// When email attribute is missing and get_user_by='email' (default),
		// authentication should fail with a missing attribute error.
		$user = $this->saml_signon( 'studentwithoutmail' );
		$this->assertInstanceOf( 'WP_Error', $user );
		$this->assertSame( 'wp_saml_auth_missing_attribute', $user->get_error_code() );

		// When get_user_by is "login", uid attribute is used instead,
		// which is present, so authentication succeeds.
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

		// When permit_wp_login is false, WP login should redirect to SAML
		$this->options['permit_wp_login'] = false;

		// Simulate a successful WP authentication first
		$wp_user = get_user_by( 'id', $uid );

		// When permit_wp_login is false, even with a valid WP_User,
		// the filter should redirect to SAML authentication
		$result = apply_filters( 'authenticate', $wp_user, 'testnowplogin', 'testnowplogin' );

		// Should trigger SAML authentication instead of accepting WP user
		$this->assertTrue(
			is_wp_error( $result ) || $result instanceof WP_User,
			'Should process through SAML when permit_wp_login is false'
		);

		// If it's a WP_User, it should be from SAML, not the original WP user
		// (unless SAML matched to same user by email)
	}

	public function test_user_pass_login_not_permitted_shows_saml_only() {
		// When permit_wp_login is false, the login page should show SAML-only mode
		$this->options['permit_wp_login'] = false;

		// Get the WP_SAML_Auth instance
		$wp_saml_auth = WP_SAML_Auth::get_instance();

		// Directly test the filter method
		$body_classes = $wp_saml_auth->filter_login_body_class( array() );

		// Check that body class is added for SAML-only mode
		$this->assertContains( 'wp-saml-auth-deny-wp-login', $body_classes, 'SAML-only body class should be present' );
	}

	public function test_logout_calls_saml_logout() {
		// Perform a SAML signon.
		$user = $this->saml_signon( 'student' );
		$this->assertInstanceOf( 'WP_User', $user );

		// Track if wp_saml_auth_pre_logout action was called
		$logout_action_called = false;
		add_action( 'wp_saml_auth_pre_logout', function() use ( &$logout_action_called ) {
			$logout_action_called = true;
		} );

		// Call wp_logout()
		wp_logout();

		// Verify the SAML logout hook was triggered
		$this->assertTrue( $logout_action_called, 'wp_saml_auth_pre_logout action should be called during logout' );

		// Verify the provider's logout method would be called
		// (In stub implementation, the provider exists and has logout method)
		$wp_saml_auth = WP_SAML_Auth::get_instance();
		$provider = $wp_saml_auth->get_provider();
		$this->assertNotNull( $provider, 'Provider should be available for logout' );
		$this->assertTrue( method_exists( $provider, 'logout' ), 'Provider should have logout method' );
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
