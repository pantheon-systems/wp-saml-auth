<?php
namespace SimpleSAML\Auth;

/**
 * Tiny stub of SimpleSAML\Auth\Simple for unit tests.
 * It is configurable via env vars so tests can toggle behavior.
 */
class Simple {
    /** @var string */
    private $sp;

    /** @var bool */
    private $authenticated = true;

    /** @var array<string, array<int, string>> */
    private $attributes = [];

    /** @var bool */
    private $allowSlo = false;

    /**
     * @param string $sp
     */
    public function __construct( $sp ) {
        $this->sp = (string) $sp;
        $this->reloadFromEnv();
    }

    private function reloadFromEnv(): void {
        $this->authenticated = getenv('WP_SAML_STUB_AUTHENTICATED') === '0' ? false : true;
        $this->allowSlo      = getenv('WP_SAML_STUB_ALLOW_SLO') === '1';

        // Defaults that match the expectations in tests unless overridden.
        $uid   = getenv('WP_SAML_STUB_UID') ?: 'student';
        $email = getenv('WP_SAML_STUB_MAIL') ?: 'student@example.org';
        $role  = getenv('WP_SAML_STUB_ROLE') ?: 'student';

        $given = getenv('WP_SAML_STUB_GIVENNAME') ?: 'Test';
        $surn  = getenv('WP_SAML_STUB_SN') ?: 'Student';

        $this->attributes = [
            'uid'                     => [ $uid ],
            'mail'                    => [ $email ],
            'eduPersonAffiliation'    => [ $role ],
            'givenName'               => [ $given ],
            'sn'                      => [ $surn ],
            // add more here if a test needs them
        ];
    }

    /**
     * WP SAML Auth may call this to force auth. Just mark as authenticated.
     */
    public function requireAuth(): void {
        $this->authenticated = true;
    }

    /**
     * Whether the user is considered logged in at the IdP.
     */
    public function isAuthenticated(): bool {
        return (bool) $this->authenticated;
    }

    /**
     * Attributes coming back from the IdP.
     *
     * @return array<string, array<int, string>>
     */
    public function getAttributes(): array {
        return $this->attributes;
    }

    /**
     * Simulate SLO. If disabled, do nothing.
     */
    public function logout( array $params = [] ): void {
        // For unit tests we don't need to actually redirect; just a no-op.
        // Tests can assert that this method could be called by enabling SLO via env.
        if ( ! $this->allowSlo ) {
            return;
        }
        // pretend we performed SLO
    }
}
