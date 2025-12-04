# Behat Integration Tests

## SimpleSAMLphp Version Testing

The Behat test suite validates SAML authentication against multiple SimpleSAMLphp versions:
- SimpleSAMLphp 1.18.0 (legacy, has known limitations)
- SimpleSAMLphp 2.0.0
- SimpleSAMLphp 2.4.0

### Known Limitations

#### SimpleSAMLphp 1.18.0

SimpleSAMLphp 1.18.0 has known test compatibility issues with the Goutte headless browser used by Behat:

**Expected Test Failures:**
- Login scenarios may fail due to redirect handling differences in SimpleSAMLphp 1.18.0
- The `ILogInAsAnAdmin()` step may not complete the SAML authentication flow
- Users may remain at `/wp-login.php` instead of being redirected to their destination

**Why This Happens:**
SimpleSAMLphp 1.18.0 (released 2018) uses older redirect patterns that don't work well with Goutte's form submission handling. Newer versions (2.0.0+) work correctly with the test infrastructure.

**Context:**
- SimpleSAMLphp 1.18.0 is **7 years old** and contains **critical security vulnerabilities** (CVE-2023-26881)
- The plugin displays critical security warnings for this version
- The minimum recommended version is **2.3.7**
- SimpleSAMLphp 1.18.0 support is maintained for backward compatibility only

**Resolution:**
These test failures are **accepted and documented** as known limitations of testing deprecated SimpleSAMLphp versions. Production users should upgrade to SimpleSAMLphp 2.3.7 or later.

#### SimpleSAMLphp 2.0.0+

SimpleSAMLphp 2.0.0 and later versions work well with the Behat test suite. Occasional failures may occur in edge case scenarios (e.g., `redirect_to` parameter handling), but core authentication flows are fully tested.

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
