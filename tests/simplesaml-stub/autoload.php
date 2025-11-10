<?php
namespace SimpleSAML\Auth;

class Simple {
	private $authed = true;
	private $attrs = [ /* uid, mail, givenName, sn, displayName … */ ];

	public function __construct($sp) { /* merge env overrides */ }
	public function requireAuth(): void {
		$forced = getenv('WPSA_TEST_SAML_AUTHED');
		$this->authed = ($forced !== false) ? (bool)(int)$forced : true;
	}
	public function isAuthenticated(): bool { return $this->authed; }
	public function getAttributes(): array   { return $this->attrs; }
	public function logout($params = [])    { $this->authed = false; return true; }
}
