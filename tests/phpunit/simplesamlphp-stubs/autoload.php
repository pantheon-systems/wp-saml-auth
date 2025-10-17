<?php
namespace SimpleSAML\Auth;

/**
 * Minimal SimpleSAMLphp stub for unit tests.
 * - Unauthenticated by default
 * - Attributes default to a "student" user
 * - Only triggers logout hook if this request actually started auth
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
        // Let tests force auth state/attributes via filters.
        $auth = \apply_filters( 'wp_saml_auth_test_is_authenticated', null );
        if ( $auth !== null ) {
            $this->authenticated = (bool) $auth;
            $this->auth_started_this_request = (bool) $auth;
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
     * - Refresh attributes if a test provided them via the filter
     */
    public function requireAuth( array $params = [] ) {
        $this->authenticated = true;
        $this->auth_started_this_request = true;

        $attrs = \apply_filters( 'wp_saml_auth_test_attributes', null );
        if ( \is_array( $attrs ) ) {
            $this->attributes = $this->normalize_attributes( $attrs );
        }
    }

    public function getAttributes() {
        $maybe = \apply_filters( 'wp_saml_auth_test_attributes', null );
        if ( \is_array( $maybe ) ) {
            return $this->normalize_attributes( $maybe );
        }
        return $this->attributes;
    }

    /**
     * Only signal a SAML logout if a SAML session was actually started
     * during this request. This avoids cross-test bleed.
     */
    public function logout( array $params = [] ) {
        if ( $this->isAuthenticated() && $this->auth_started_this_request ) {
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

