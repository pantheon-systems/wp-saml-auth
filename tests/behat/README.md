# Behat Integration Tests

## SimpleSAMLphp Version Testing

The Behat test suite validates SAML authentication against multiple SimpleSAMLphp versions:

- SimpleSAMLphp 1.18.0 (legacy, has known limitations)
- SimpleSAMLphp 2.0.0
- SimpleSAMLphp 2.4.0

### Known Limitations

#### SimpleSAMLphp 1.18.0

SimpleSAMLphp 1.18.0 has known test compatibility issues with the Goutte headless browser used by Behat.

**Limited Test Coverage:**

Due to redirect handling differences in SimpleSAMLphp 1.18.0, the test suite for this version only runs:

- **Basic login test**: Verifies that users can authenticate successfully
- **Critical vulnerability notice test**: Confirms that administrators see the CVE-2023-26881 security alert

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

SimpleSAMLphp 2.0.0 and later versions work well with the Behat test suite. Core authentication flows are fully tested.

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

## Running Tests Locally

Tests are designed to run in CI/CD via GitHub Actions. Running locally requires:

- Terminus CLI with Pantheon authentication
- Access to the `wp-saml-auth` Pantheon site
- SimpleSAMLphp installation on the Pantheon environment

See `.github/workflows/behat-tests.yml` for the complete test setup.
