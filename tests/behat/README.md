# Behat Integration Tests

## Connection Type Testing

WP SAML Auth supports two SAML connection types:

1. **`internal`** (default) - Uses the bundled OneLogin SAML PHP library
2. **`simplesamlphp`** - Uses separately-installed SimpleSAMLphp library

### Current Test Implementation

Tests currently run with a single connection type, configured in `bin/fixtures/functions.php`:

- Currently set to `connection_type='simplesamlphp'` to test SimpleSAMLphp functionality and warning messages
- The plugin's default is `'internal'` (OneLogin connector)

### Recommended Comprehensive Test Coverage

For thorough validation, tests should cover both connection types across all scenarios:

**Functionality Tests (login, authentication):**
| SimpleSAMLphp Version | `connection_type='simplesamlphp'` | `connection_type='internal'` |
|-----------------------|----------------------------------|------------------------------|
| 1.18.0 | ✓ Test SAML auth works | ✓ Test OneLogin works |
| 2.0.0 | ✓ Test SAML auth works | ✓ Test OneLogin works |
| 2.4.0 | ✓ Test SAML auth works | ✓ Test OneLogin works |

**Warning Message Tests:**
| SimpleSAMLphp Version | `connection_type='simplesamlphp'` | `connection_type='internal'` |
|-----------------------|----------------------------------|------------------------------|
| 1.18.0 | ✓ Critical warning shows | ✓ NO warning (not using SimpleSAMLphp) |
| 2.0.0 | ✓ Security warning shows | ✓ NO warning (not using SimpleSAMLphp) |
| 2.4.0 | ✓ NO warning (current) | ✓ NO warning (not using SimpleSAMLphp) |

This comprehensive approach validates:

- Both connectors work independently
- Warnings only show when using SimpleSAMLphp (`connection_type='simplesamlphp'`)
- Warnings correctly suppress for OneLogin users (`connection_type='internal'`)
- The `&& $connection_type === 'simplesamlphp'` conditional checks function correctly

### Historical Context

**May 2019:** The plugin's default connection type was set to `'internal'` (bundled OneLogin library).
*Commit: [8866ecd](https://github.com/pantheon-systems/wp-saml-auth/commit/8866ecd) - "Remove 'connection_type' option because 'internal' is the only supported"*

**June 2025:** SimpleSAMLphp security warnings were added to alert users of vulnerable versions (CVE-2023-26881).
*PR #402: [89a3d5e](https://github.com/pantheon-systems/wp-saml-auth/pull/402) - "SITE-4575: Update SimpleSAMLphp security requirements to 2.3.7"*

**December 2025:** Test configuration was updated to use `connection_type='simplesamlphp'` to enable testing of SimpleSAMLphp-specific functionality and warning messages.
*Branch: `newAdaptWarningMessage` - Commit: [d2c743a](https://github.com/pantheon-systems/wp-saml-auth/commit/d2c743a) - "Fix SimpleSamlPHP fonctionnality"*

## SimpleSAMLphp Version Testing

The Behat test suite validates SAML authentication against multiple SimpleSAMLphp versions:

- SimpleSAMLphp 1.18.0 (legacy, has known limitations)
- SimpleSAMLphp 2.0.0
- SimpleSAMLphp 2.4.0

### Known Limitations

#### SimpleSAMLphp 1.18.0

SimpleSAMLphp 1.18.0 has known test compatibility issues with the Goutte headless browser used by Behat.

**Limited Test Coverage:**

Due to redirect handling differences in SimpleSAMLphp 1.18.0, the test suite for this version **skips all Pantheon WordPress upstream tests** and only runs:

- **Basic login test**: Verifies that users can authenticate successfully
- **Critical vulnerability notice test**: Confirms that administrators see the CVE-2023-26881 security alert

The Pantheon upstream tests (comments, users, terms, etc.) are skipped because they require reliable admin login, which is problematic with 1.18.0's redirect handling.

**Why Limited Testing:**

SimpleSAMLphp 1.18.0 (released 2018) uses older redirect patterns that don't work reliably with Goutte's form submission handling. Rather than maintain brittle tests, we focus on essential functionality verification.

**Context:**

- SimpleSAMLphp 1.18.0 is **7 years old** and contains **critical security vulnerabilities** (CVE-2023-26881)
- The plugin displays critical security warnings for this version
- The minimum recommended version is **2.3.7**
- SimpleSAMLphp 1.18.0 support is maintained for backward compatibility only

**Resolution:**

Production users should upgrade to SimpleSAMLphp 2.3.7 or later. The limited test suite ensures basic functionality works while acknowledging the deprecated status of this version.

#### SimpleSAMLphp 2.0.0+

SimpleSAMLphp 2.0.0 and later versions work well with the Behat test suite.

**Full Test Coverage:**

- **Pantheon WordPress upstream tests**: All standard WordPress functionality (comments, users, terms, themes, plugins, etc.)
- **SAML-specific tests**:
  - Basic login with employee credentials
  - Basic login with student credentials
  - Invalid password error handling
  - Security warning admin notice (2.0.0 only, as it's below the recommended version)

#### redirect_to Parameter Limitation

The WordPress `redirect_to` parameter (used to redirect users to a specific page after login) is not tested for SimpleSAMLphp authentication because:

1. **SimpleSAMLphp controls the entire authentication flow**: Unlike OneLogin where WordPress manages the login process, SimpleSAMLphp handles authentication and redirects independently
2. **WordPress login hooks are bypassed**: The `login_redirect` filter and other WordPress login mechanisms don't apply when SimpleSAMLphp completes authentication
3. **Session state differences**: SimpleSAMLphp may maintain session state differently than WordPress expects

While the plugin attempts to handle `redirect_to` by passing it through SimpleSAMLphp's ReturnTo parameter, this functionality is not guaranteed to work consistently across different SimpleSAMLphp versions and configurations. Users requiring guaranteed redirect functionality should use the OneLogin (internal) connection type instead.

## Test Infrastructure

The tests use:

- **Goutte**: Headless browser without JavaScript execution
- **Pantheon multidev environments**: Temporary test environments created per test run
- **SimpleSAMLphp**: Deployed on Pantheon alongside WordPress for integration testing

