<?php
namespace SimpleSAML\Auth;

class Simple {
    private static $authenticated = true;
    private static $attributes = [
        'uid'                  => ['student'],
        'mail'                 => ['student@example.org'],
        'eduPersonAffiliation' => ['student'],
    ];
    private static $logoutCalled = false;

    public function __construct(string $spEntityId) {}

    public function isAuthenticated(): bool {
        return self::$authenticated;
    }

    // CHANGE: make this a *true* no-op. Do not mutate authenticated state here.
    public function requireAuth(): void {
        // no-op in tests
    }

    public function getAttributes(): array {
        return self::$attributes;
    }

    public function logout(?string $returnTo = null): void {
        // Only record SLO if we’re explicitly allowing it via env (default off).
        if ( getenv('WP_SAML_STUB_ALLOW_SLO') === '1' ) {
            self::$logoutCalled = true;
        }
        // Otherwise a no-op.
    }

    // --- helpers used by tests if needed
    public static function _setAuthenticated(bool $state): void { self::$authenticated = $state; }
    public static function _setAttributes(array $attributes): void { self::$attributes = $attributes; }
    public static function _getLogoutCalled(): bool { return self::$logoutCalled; }
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
