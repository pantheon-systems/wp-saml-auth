<?php
namespace SimpleSAML\Auth;

/**
 * Minimal SimpleSAMLphp stub for unit tests.
 * - Unauthenticated by default
 * - Default attributes represent a "student" user
 * - getAttributes() always returns attributes (even if not authenticated yet)
 * - Logout hook only fires if (a) this request started auth AND (b) a test
 *   explicitly allows it via the wp_saml_auth_test_allow_logout_hook filter.
 */
class Simple {
    private $authenticated = false;
    private $auth_started_this_request = false;

    private $attributes = [
        'uid'                  => ['student'],
        'mail'                 => ['test-student@example.com'],
        'eduPersonAffiliation' => ['student'],
    ];

    public function __construct( $source = null ) {
        // Allow tests to pre-seed auth state and attributes via filters.
        $forcedAuth = \apply_filters( 'wp_saml_auth_test_is_authenticated', null );
        if ( $forcedAuth !== null ) {
            $this->authenticated = (bool) $forcedAuth;
            $this->auth_started_this_request = (bool) $forcedAuth;
        }

        $attrs = \apply_filters( 'wp_saml_auth_test_attributes', null );
        if ( \is_array( $attrs ) ) {
            $this->attributes = $this->normalize_attributes( $attrs );
        }
    }

    public function isAuthenticated() {
        $forced = \apply_filters( 'wp_saml_auth_test_is_authenticated', null );
        return $forced !== null ? (bool) $forced : $this->authenticated;
    }

    /**
     * Simulate IdP auth requirement.
     * - Flip to authenticated
     * - Refresh attributes if provided by a test filter
     */
    public function requireAuth( array $params = [] ) {
        $this->authenticated = true;
        $this->auth_started_this_request = true;

        $attrs = \apply_filters( 'wp_saml_auth_test_attributes', null );
        if ( \is_array( $attrs ) ) {
            $this->attributes = $this->normalize_attributes( $attrs );
        }
    }

    /**
     * Always return the attributes array so tests that peek at attributes
     * prior to requireAuth() still see the expected values/persona.
     */
    public function getAttributes() {
        $maybe = \apply_filters( 'wp_saml_auth_test_attributes', null );
        if ( \is_array( $maybe ) ) {
            return $this->normalize_attributes( $maybe );
        }
        return $this->attributes;
    }

    /**
     * Only signal a SAML logout if:
     *  - we are authenticated,
     *  - AND this request actually started auth,
     *  - AND the test explicitly allows the hook (default false).
     */
    public function logout( array $params = [] ) {
        $allow = (bool) \apply_filters( 'wp_saml_auth_test_allow_logout_hook', false );
        if ( $allow && $this->isAuthenticated() && $this->auth_started_this_request ) {
            \do_action( 'wp_saml_auth_test_logout_called', $params );
        }
        return null;
    }

    private function normalize_attributes( $attrs ) {
        $out = [];
        foreach ( $attrs as $k => $v ) {
            $out[ $k ] = \is_array( $v ) ? array_values( $v ) : [ (string) $v ];
        }
        return $out;
    }
}
