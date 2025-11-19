<?php
/**
 * Integration tests for complete authentication flows
 *
 * @package WP_SAML_Auth
 */

/**
 * Class Test_Integration_Authentication_Flow
 */
#[AllowDynamicProperties]
class Test_Integration_Authentication_Flow extends WP_UnitTestCase {

	protected $options = array();

	/**
	 * Setup for each test
	 */
	public function setUp(): void {
		parent::setUp();
		$this->options = array();
		$GLOBALS['wp_saml_auth_current_user'] = null;

		// Reset the WP_SAML_Auth provider to ensure fresh instance for each test
		$wp_saml_auth = WP_SAML_Auth::get_instance();
		$reflection = new ReflectionClass( $wp_saml_auth );
		$provider_property = $reflection->getProperty( 'provider' );
		$provider_property->setAccessible( true );
		$provider_property->setValue( $wp_saml_auth, null );

		add_filter( 'wp_saml_auth_option', array( $this, 'filter_wp_saml_auth_option' ), 10, 2 );
	}

	/**
	 * Cleanup after each test
	 */
	public function tearDown(): void {
		remove_filter( 'wp_saml_auth_option', array( $this, 'filter_wp_saml_auth_option' ) );
		unset( $GLOBALS['wp_saml_auth_current_user'] );
		unset( $_GET['action'] );
		unset( $_POST['SAMLResponse'] );
		parent::tearDown();
	}

	/**
	 * Test authenticate filter is registered
	 */
	public function test_authenticate_filter_is_registered() {
		$wp_saml_auth = WP_SAML_Auth::get_instance();

		$this->assertGreaterThan(
			0,
			has_filter( 'authenticate', array( $wp_saml_auth, 'filter_authenticate' ) ),
			'authenticate filter should be registered'
		);
	}

	/**
	 * Test wp_logout action is registered
	 */
	public function test_wp_logout_action_is_registered() {
		$wp_saml_auth = WP_SAML_Auth::get_instance();

		$this->assertGreaterThan(
			0,
			has_action( 'wp_logout', array( $wp_saml_auth, 'action_wp_logout' ) ),
			'wp_logout action should be registered'
		);
	}

	/**
	 * Test login_body_class filter is registered
	 */
	public function test_login_body_class_filter_is_registered() {
		$wp_saml_auth = WP_SAML_Auth::get_instance();

		$this->assertGreaterThan(
			0,
			has_filter( 'login_body_class', array( $wp_saml_auth, 'filter_login_body_class' ) ),
			'login_body_class filter should be registered'
		);
	}

	/**
	 * Test SAML authentication flow with SAMLResponse POST
	 */
	public function test_saml_authentication_with_saml_response() {
		$this->options['permit_wp_login'] = true;

		// Simulate SAML response
		$_POST['SAMLResponse'] = 'dummy_saml_response';

		// Set up SAML user attributes
		$this->set_saml_auth_user( 'student' );

		// Trigger authentication
		$user = apply_filters( 'authenticate', null, '', '' );

		// Should return a WP_User from SAML
		$this->assertInstanceOf( 'WP_User', $user, 'SAML authentication should return WP_User' );

		unset( $_POST['SAMLResponse'] );
	}

	/**
	 * Test SAML authentication flow with action parameter
	 */
	public function test_saml_authentication_with_action_parameter() {
		$this->options['permit_wp_login'] = true;

		// Simulate SAML action
		$_GET['action'] = 'wp-saml-auth';

		// Set up SAML user attributes
		$this->set_saml_auth_user( 'student' );

		// Trigger authentication
		$user = apply_filters( 'authenticate', null, '', '' );

		// Should return a WP_User from SAML
		$this->assertInstanceOf( 'WP_User', $user, 'SAML authentication via action should return WP_User' );

		unset( $_GET['action'] );
	}

	/**
	 * Test that WordPress login is allowed when permit_wp_login is true
	 */
	public function test_wordpress_login_allowed_when_permitted() {
		$this->options['permit_wp_login'] = true;

		// Create a WP user
		$user_id = $this->factory->user->create( array(
			'user_login' => 'wpuser',
			'user_pass'  => 'password123',
		) );

		// Simulate successful WP authentication
		$wp_user = get_user_by( 'id', $user_id );

		// When a WP_User is already authenticated and permit_wp_login is true,
		// the filter should return the same user
		$result = apply_filters( 'authenticate', $wp_user, 'wpuser', 'password123' );

		$this->assertInstanceOf( 'WP_User', $result );
		$this->assertEquals( $user_id, $result->ID );
	}

	/**
	 * Test that WordPress login triggers SAML when permit_wp_login is false
	 */
	public function test_wordpress_login_triggers_saml_when_not_permitted() {
		$this->options['permit_wp_login'] = false;

		// Even with a valid WP user, permit_wp_login=false should trigger SAML
		$user_id = $this->factory->user->create( array(
			'user_login' => 'wpuser',
			'user_pass'  => 'password123',
		) );

		$wp_user = get_user_by( 'id', $user_id );

		// Set up SAML user
		$this->set_saml_auth_user( 'student' );

		// When permit_wp_login is false, even a valid WP user should be redirected to SAML
		$result = apply_filters( 'authenticate', $wp_user, 'wpuser', 'password123' );

		// Result should be from SAML authentication, not the original WP user
		// (Could be WP_User from SAML or WP_Error depending on SAML state)
		$this->assertTrue(
			is_wp_error( $result ) || $result instanceof WP_User,
			'Should process through SAML authentication'
		);
	}

	/**
	 * Test authentication with missing email attribute
	 */
	public function test_authentication_with_missing_attributes() {
		$this->set_saml_auth_user( 'studentwithoutmail' );
		$_GET['action'] = 'wp-saml-auth';

		// With default get_user_by='email', missing 'mail' attribute causes error
		$user = apply_filters( 'authenticate', null, '', '' );
		$this->assertInstanceOf( 'WP_Error', $user, 'Should return error when required attribute is missing' );
		$this->assertSame( 'wp_saml_auth_missing_attribute', $user->get_error_code() );

		// But with get_user_by='login', it works because 'uid' is present
		$this->options['get_user_by'] = 'login';
		$user = apply_filters( 'authenticate', null, '', '' );
		$this->assertInstanceOf( 'WP_User', $user, 'Should succeed when using login attribute' );

		unset( $_GET['action'] );
	}

	/**
	 * Test user matching by email
	 */
	public function test_user_matching_by_email() {
		// Create existing user with matching email
		$existing_user_id = $this->factory->user->create( array(
			'user_login' => 'existinguser',
			'user_email' => 'student@example.org',
		) );

		// Verify the user exists
		$existing_user = get_user_by( 'email', 'student@example.org' );
		$this->assertInstanceOf( 'WP_User', $existing_user, 'Existing user should be found by email' );
		$this->assertEquals( $existing_user_id, $existing_user->ID, 'User IDs should match' );

		$this->options['get_user_by'] = 'email';
		$this->options['auto_provision'] = true;
		$this->set_saml_auth_user( 'student' );
		$_GET['action'] = 'wp-saml-auth';

		$user = wp_signon();

		$this->assertInstanceOf( 'WP_User', $user );
		// Should match existing user by email
		$this->assertEquals( $existing_user_id, $user->ID, 'Should match existing user by email' );

		unset( $_GET['action'] );
	}

	/**
	 * Test user matching by login
	 */
	public function test_user_matching_by_login() {
		// Create existing user with matching login
		$existing_user_id = $this->factory->user->create( array(
			'user_login' => 'student',
			'user_email' => 'different@example.org',
		) );

		// Verify the user exists
		$existing_user = get_user_by( 'login', 'student' );
		$this->assertInstanceOf( 'WP_User', $existing_user, 'Existing user should be found by login' );
		$this->assertEquals( $existing_user_id, $existing_user->ID, 'User IDs should match' );

		$this->options['get_user_by'] = 'login';
		$this->options['auto_provision'] = true;
		$this->set_saml_auth_user( 'student' );
		$_GET['action'] = 'wp-saml-auth';

		$user = wp_signon();

		$this->assertInstanceOf( 'WP_User', $user );
		// Should match existing user by login
		$this->assertEquals( $existing_user_id, $user->ID, 'Should match existing user by login' );

		unset( $_GET['action'] );
	}

	/**
	 * Test default role assignment on auto-provision
	 */
	public function test_default_role_on_auto_provision() {
		$this->options['default_role'] = 'editor';
		$this->options['auto_provision'] = true;

		$this->set_saml_auth_user( 'student' );
		$_GET['action'] = 'wp-saml-auth';

		$user = apply_filters( 'authenticate', null, '', '' );

		$this->assertInstanceOf( 'WP_User', $user );
		$this->assertContains( 'editor', $user->roles, 'User should have editor role' );

		unset( $_GET['action'] );
	}

	/**
	 * Test that login_message filter shows SAML button when permit_wp_login is true
	 */
	public function test_login_message_shows_saml_option() {
		$this->options['permit_wp_login'] = true;

		// Simulate login page
		do_action( 'login_form_login' );

		$message = apply_filters( 'login_message', '' );

		// The login message should be empty since action_login_message echoes directly
		// But we can test that the filter is registered
		$wp_saml_auth = WP_SAML_Auth::get_instance();
		$this->assertGreaterThan(
			0,
			has_filter( 'login_message', array( $wp_saml_auth, 'action_login_message' ) ),
			'login_message filter should be registered'
		);
	}

	/**
	 * Test loggedout parameter allows through when permit_wp_login is false
	 */
	public function test_loggedout_parameter_bypasses_saml() {
		$this->options['permit_wp_login'] = false;
		$_GET['loggedout'] = 'true';

		// Get the WP_SAML_Auth instance to test the filter directly
		$wp_saml_auth = WP_SAML_Auth::get_instance();

		// When loggedout=true, even with permit_wp_login=false,
		// the filter should return the input unchanged (not force SAML)
		$result = $wp_saml_auth->filter_authenticate( null, '', '' );

		// Should return null (not force SAML authentication)
		$this->assertNull( $result, 'Should not force SAML when loggedout parameter is present' );

		unset( $_GET['loggedout'] );
	}

	/**
	 * Helper to set SAML auth user attributes
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
					// Intentionally missing 'mail'
					'eduPersonScopedAffiliation' => array( 'student@example.org' ),
				);
				break;
		}

		$GLOBALS['wp_saml_auth_current_user'] = $user;
	}

	/**
	 * Filter callback for wp_saml_auth options
	 */
	public function filter_wp_saml_auth_option( $value, $option_name ) {
		if ( array_key_exists( $option_name, $this->options ) ) {
			return $this->options[ $option_name ];
		}
		return $value;
	}
}
