<?php
namespace SimpleSAML\Auth;

/**
 * Test stub for SimpleSAML\Auth\Simple used by unit tests.
 */
class Simple {
    /** @var bool */
    private static $authenticated = true;

    /** @var array<string, array<int, string>> */
    private static $attributes = [
        'uid'                    => ['student'],
        'mail'                   => ['student@example.org'],
        'eduPersonAffiliation'   => ['student'],
    ];

    /** @var bool */
    private static $logoutCalled = false;

    /** @var string */
    private $spEntityId;

    public function __construct(string $spEntityId) {
        $this->spEntityId = $spEntityId;
    }

    /** Hooks the same way as real SimpleSAML. */
    public function isAuthenticated(): bool {
        return self::$authenticated;
    }

    /** The plugin sometimes calls requireAuth(); make it a no-op if already “authenticated”. */
    public function requireAuth(): void {
        // In our tests, we just assume the IdP flow completed when authenticated is true.
        if (!self::$authenticated) {
            self::$authenticated = true;
        }
    }

    /**
     * Return SAML attributes in the same structure as SimpleSAML:
     *   [ 'attrName' => ['value1', 'value2'] ]
     */
    public function getAttributes(): array {
        return self::$attributes;
    }

    public function logout(?string $returnTo = null): void {
        self::$logoutCalled = true;
        // Do nothing else in tests.
    }

    public function login(array $params = []): void {
        // noop in tests
    }

    // --- Utilities the tests (or bootstrap) can manipulate via filters if needed.

    /** @internal for tests */
    public static function _setAuthenticated(bool $state): void {
        self::$authenticated = $state;
    }

    /** @internal for tests */
    public static function _setAttributes(array $attributes): void {
        self::$attributes = $attributes;
    }

    /** @internal for tests */
    public static function _getLogoutCalled(): bool {
        return self::$logoutCalled;
    }

    /** @internal for tests */
    public static function _reset(): void {
        self::$authenticated = true;
        self::$attributes = [
            'uid'                  => ['student'],
            'mail'                 => ['student@example.org'],
            'eduPersonAffiliation' => ['student'],
        ];
        self::$logoutCalled = false;
    }
}
