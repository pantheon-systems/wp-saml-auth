<?php

/**
 * Test all variations of authentication.
 */
#[AllowDynamicProperties]
class Test_Authentication extends WP_UnitTestCase {

	private $option = array();

	public function setUp(): void {
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

	public function data_saml_lookup_field_comparison() {
		return array(
			'exact email authenticates'          => array( 'email', 'wpreport@example.test', true ),
			'case-variant email authenticates'   => array( 'email', 'WpReport@Example.test', true ),
			'accent-variant email is rejected'   => array( 'email', 'wpréport@example.test', false ),
			'exact login authenticates'          => array( 'login', 'wpreport', true ),
			'case-variant login authenticates'   => array( 'login', 'WpReport', true ),
			'accent-variant login is rejected'   => array( 'login', 'wpréport', false ),
		);
	}

	/**
	 * SITE-6023: an attacker who signs in via SAML for the first time with an
	 * accented variant of a victim's email/login must NOT be authenticated as
	 * the victim.
	 *
	 * This exercises the disclosed attack directly: auto_provision is left at
	 * its default (true), so a first-time SAML sign-on would normally create a
	 * new user. Because the accent-insensitive database collation makes
	 * get_user_by() return the victim, the pre-fix plugin skips provisioning and
	 * logs the attacker straight into the victim's account. The fix rejects the
	 * near-match before that happens. Case-only differences stay valid
	 * (RFC 5321; WordPress usernames are case-insensitive).
	 *
	 * @dataProvider data_saml_lookup_field_comparison
	 */
	public function test_saml_lookup_field_comparison( $get_user_by, $saml_value, $expect_login ) {
		$this->options['get_user_by'] = $get_user_by;

		$victim_id = $this->factory->user->create( array(
			'user_login' => 'wpreport',
			'user_email' => 'wpreport@example.test',
		) );

		// Precondition: the database lookup finds the victim for every variant.
		// With an accent-insensitive collation (e.g. utf8mb4_unicode_520_ci),
		// this collision is what makes the account takeover possible.
		$found = get_user_by( $get_user_by, $saml_value );
		$this->assertInstanceOf( 'WP_User', $found );
		$this->assertEquals( $victim_id, $found->ID );

		if ( ! $expect_login ) {
			// The rejection cases only reproduce the vulnerability if the users
			// table collation actually treats the accented value as equal. If a
			// future WordPress/DB change made it accent-sensitive, get_user_by()
			// above would still match by case only, but the fix's mismatch check
			// would no longer be the thing under test. Skip loudly rather than
			// pass for the wrong reason.
			$this->skip_unless_accent_insensitive( $get_user_by );
		}

		$attribute = 'email' === $get_user_by ? 'mail' : 'uid';
		$user = $this->saml_signon_with_attributes( array( $attribute => array( $saml_value ) ) );

		if ( $expect_login ) {
			$this->assertInstanceOf( 'WP_User', $user );
			$this->assertEquals( $victim_id, $user->ID );
			$this->assertEquals( $victim_id, get_current_user_id() );
			return;
		}

		// The near-match must be rejected, no one logged in...
		$this->assertInstanceOf( 'WP_Error', $user );
		$this->assertEquals( 'wp_saml_auth_attribute_mismatch', $user->get_error_code() );
		$this->assertEquals( 0, get_current_user_id() );

		// ...and, crucially, auto-provision must not have silently created a
		// second (attacker) account. Only the victim we seeded should exist.
		$this->assertCount( 1, get_users( array( 'search' => 'wpreport', 'search_columns' => array( 'user_login', 'user_email' ) ) ) );
	}

	/**
	 * Skip the test unless the users table's collation treats an accented
	 * character as equal to its unaccented form. The SITE-6023 collision only
	 * exists under an accent-insensitive collation (e.g. utf8mb4_unicode_520_ci).
	 *
	 * @param string $get_user_by Lookup field ('email' or 'login'), used to pick
	 *                            the column whose collation governs the lookup.
	 */
	private function skip_unless_accent_insensitive( $get_user_by ) {
		global $wpdb;
		$column = 'email' === $get_user_by ? 'user_email' : 'user_login';
		$collation = $wpdb->get_var(
			$wpdb->prepare(
				'SELECT COLLATION_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = %s AND TABLE_NAME = %s AND COLUMN_NAME = %s',
				DB_NAME,
				$wpdb->users,
				$column
			)
		);
		if ( empty( $collation ) ) {
			$this->markTestSkipped( "Could not determine collation of {$wpdb->users}.{$column}." );
		}
		$accent_insensitive = $wpdb->get_var( "SELECT 'wpréport' = 'wpreport' COLLATE {$collation}" );
		if ( '1' !== (string) $accent_insensitive ) {
			$this->markTestSkipped(
				"SITE-6023 regression requires an accent-insensitive collation on {$wpdb->users}.{$column}; "
				. "found '{$collation}', which is accent-sensitive, so the account-takeover collision cannot be reproduced here."
			);
		}
	}

	private function saml_signon_with_attributes( array $attributes ) {
		$GLOBALS['wp_saml_auth_current_user'] = $attributes;
		$_GET['action'] = 'wp-saml-auth';
		return wp_signon();
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

	/**
	* @param string $value
	* @param string|null $option_name
	* @return string
	*/
	public function filter_wp_saml_auth_option( $value, $option_name ) {
		if ( isset( $this->options[ $option_name ] ) ) {
			return $this->options[ $option_name ];
		}
		return $value;
	}

	public function tearDown(): void {
		remove_filter( 'wp_saml_auth_option', array( $this, 'filter_wp_saml_auth_option' ) );
		parent::tearDown();
	}

}
