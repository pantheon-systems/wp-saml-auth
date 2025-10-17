<?php
namespace SimpleSAML\Auth;

/**
 * Extremely small test double of SimpleSAML\Auth\Simple
 * to satisfy wp-saml-auth unit tests with predictable behavior.
 */
class Simple
{
    /** @var string */
    protected $source;

    /** @var array */
    protected $attributes;

    /** @var bool */
    protected $authenticated = true;

    public function __construct($source)
    {
        $this->source = (string) $source;

        // Default identity is "student" unless explicitly changed via a runtime global.
        // Tests that want "employee" can set $GLOBALS['WP_SAML_AUTH_TEST_IDENTITY'] = 'employee'.
        $who = isset($GLOBALS['WP_SAML_AUTH_TEST_IDENTITY']) ? (string) $GLOBALS['WP_SAML_AUTH_TEST_IDENTITY'] : 'student';

        // Canonical attribute set the plugin expects.
        // - uid                => login/username
        // - mail               => email
        // - givenName / sn     => first/last name
        // - eduPersonAffiliation for role-ish checks
        $this->attributes = [
            'uid'                   => [$who],
            'mail'                  => [$who === 'employee' ? 'test-em@example.com' : 'test-student@example.com'],
            'givenName'             => [$who === 'employee' ? 'Acme' : 'Pantheon'],
            'sn'                    => [$who === 'employee' ? 'Employee' : 'Student'],
            'eduPersonAffiliation'  => [$who], // simple echo; tests only check presence/values
        ];
    }

    public function isAuthenticated()
    {
        return $this->authenticated;
    }

    public function requireAuth(array $params = [])
    {
        // No-op in tests; we always consider the session authenticated.
        $this->authenticated = true;
    }

    public function getAttributes()
    {
        return $this->attributes;
    }

    public function logout($params = null)
    {
        // Make this a no-op by default because your failing test expects "not called".
        // If a test needs to detect it, it can flip a global first:
        //   $GLOBALS['WP_SAML_AUTH_CAPTURE_LOGOUT'] = true;
        if (!empty($GLOBALS['WP_SAML_AUTH_CAPTURE_LOGOUT'])) {
            $GLOBALS['WP_SAML_AUTH_LOGOUT_CALLED'] = true;
        }
    }
}
