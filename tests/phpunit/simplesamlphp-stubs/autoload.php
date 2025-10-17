<?php
/**
 * Minimal SimpleSAMLphp stubs for unit tests.
 *
 * The plugin calls \SimpleSAML\Auth\Simple. We emulate enough to be deterministic.
 */

namespace SimpleSAML\Auth;

class Simple {
	/** @var bool */
	private $authenticated = false;

	/**
	 * Attributes returned by IdP.
	 * The default user is "student" to match tests that expect an auto-provisioned user 'student'.
	 * Individual tests can override via the 'wp_saml_auth_test_attributes' filter.
	 *
	 * @var array<string, array<int,string>>
	 */
	private $attributes = [
		'uid'                  => ['student'],
		'mail'                 => ['test-student@example.com'],
		'eduPersonAffiliation' => ['student'],
	];

	/**
	 * @param string|null $source Ignored (kept for signature compatibility).
	 */
	public function __construct( $source = null ) {
		// Start unauthenticated; the plugin typically calls requireAuth() on SAML flows.
		$this->authenticated = (bool) \apply_filters( 'wp_saml_auth_test_is_authenticated', false );

		$attrs = \apply_filters( 'wp_saml_auth_test_attributes', null );
		if ( \is_array( $attrs ) ) {
			// IMPORTANT: do NOT merge with defaults; tests that remove an attribute must fail.
			$this->attributes = $this->normalize_attributes( $attrs );
		}
	}

	/**
	 * Whether user is authenticated with the IdP.
	 */
	public function isAuthenticated() {
		return (bool) \apply_filters( 'wp_saml_auth_test_is_authenticated', $this->authenticated );
	}

	/**
	 * Force authentication (what the plugin expects when starting SAML login).
	 */
	public function requireAuth( array $params = [] ) {
		$this->authenticated = true;
	}

	/**
	 * Return SAML attributes as array-of-arrays.
	 *
	 * @return array<string, array<int,string>>
	 */
	public function getAttributes() {
		$maybe = \apply_filters( 'wp_saml_auth_test_attributes', null );
		if ( \is_array( $maybe ) ) {
			return $this->normalize_attributes( $maybe );
		}
		return $this->attributes;
	}

	/**
	 * Record that logout was called (tests can assert via action), return null.
	 */
	public function logout( array $params = [] ) {
		\do_action( 'wp_saml_auth_test_logout_called', $params );
		return null;
	}

	/**
	 * Ensure attributes have correct shape (array<string, array<int,string>>).
	 *
	 * @param array<string, mixed> $attrs
	 * @return array<string, array<int,string>>
	 */
	private function normalize_attributes( $attrs ) {
		$out = [];
		foreach ( $attrs as $k => $v ) {
			$out[ $k ] = \is_array( $v ) ? array_values( $v ) : [ (string) $v ];
		}
		return $out;
	}
}
