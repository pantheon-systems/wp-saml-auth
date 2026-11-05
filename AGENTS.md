# WP SAML Auth (Pantheon)

**Plugin:** WP SAML Auth
**Version:** 2.3.2-dev
**License:** GPLv2 or later
**Author:** Pantheon
**Requires PHP:** 7.4
**Tested up to:** WordPress 6.9

## Overview

SAML 2.0 Single Sign-On for WordPress. IdP-agnostic — works with any SAML 2.0 compliant Identity Provider (Okta, Azure AD/Entra ID, Google Workspace, ADFS, Shibboleth, etc.). No upsell, no license required, no feature gating. All features are available in the single free plugin.

Supports two SAML backends via the `connection_type` option:

- **`simplesamlphp`** (default) — delegates to a separately-installed SimpleSAMLphp instance. SimpleSAMLphp must be installed alongside WordPress; it is not bundled.
- **`internal`** — uses the bundled `onelogin/php-saml` library (with `robrichards/xmlseclibs`) via Composer. Run `composer install` in the plugin directory to populate `vendor/` before using this mode.

## Directory Structure

```
wp-saml-auth.php                   Main plugin file; bootstraps autoloader and main class
inc/
  class-wp-saml-auth.php           Core controller: ACS endpoint, login flow, user lookup/creation
  class-wp-saml-auth-cli.php       WP-CLI commands
  class-wp-saml-auth-options.php   Options abstraction; reads from DB or wp_saml_auth_option filter
  class-wp-saml-auth-settings.php  Admin settings UI (Settings → WP SAML Auth)
vendor/                            Composer dependencies (not committed; run `composer install`)
                                   Required only for connection_type=internal
languages/                         .pot + French translations
```

## Authentication Flow

### SimpleSAMLphp mode (default)

1. User hits the login page. If `permit_wp_login` is false, plugin immediately initiates SSO.
2. `$provider->requireAuth()` redirects to SimpleSAMLphp, which handles the full SAML exchange with the IdP.
3. On return, `$provider->getAttributes()` retrieves the assertion attributes.
4. User is looked up by email or login. If found, logged in. If not found and `auto_provision` is enabled, a new WordPress user is created.
5. On logout, `$provider->logout()` delegates to SimpleSAMLphp's SLO handling.

### Internal mode (`connection_type = 'internal'`)

1. User hits the login page. If `permit_wp_login` is false, plugin immediately initiates SSO.
2. `$provider->login()` builds a signed `AuthnRequest` and redirects to the IdP SSO URL.
3. IdP authenticates the user and POSTs a `SAMLResponse` back to `wp-login.php`.
4. Plugin calls `$provider->processResponse()` — validates XML signature against the IdP's X.509 certificate, checks timestamps, extracts the assertion.
5. Attributes are pulled via `$provider->getAttributes()` and mapped to WordPress user fields per configuration.
6. User is looked up by email or login. If found, logged in. If not found and `auto_provision` is enabled, a new WordPress user is created.
7. On logout, if SLO is configured, `$provider->logout()` initiates a SAML logout request to the IdP.

## Configuration

Two approaches — **only one can be active at a time**. If the `wp_saml_auth_option` filter is registered, the admin UI is fully disabled.

### Approach 1: Admin UI

Settings → WP SAML Auth. Values are stored in `wp_options` under `wp_saml_auth_settings`. Use this for simple deployments.

### Approach 2: Filter (code-based)

Place in a mu-plugin or `wp-config.php`.

**SimpleSAMLphp mode (default):**

```php
add_filter( 'wp_saml_auth_option', function( $value, $option_name ) {
    $config = [
        'connection_type'       => 'simplesamlphp',
        'simplesamlphp_autoload' => '/path/to/simplesamlphp/vendor/autoload.php',
        'auth_source'           => 'default-sp',  // must match a source in SSP config
        'auto_provision'        => true,
        'permit_wp_login'       => true,
        'get_user_by'           => 'email',
        'user_login_attribute'  => 'uid',
        'user_email_attribute'  => 'mail',
        'display_name_attribute' => 'display_name',
        'first_name_attribute'  => 'first_name',
        'last_name_attribute'   => 'last_name',
        'default_role'          => get_option( 'default_role' ),
    ];
    return $config[ $option_name ] ?? $value;
}, 10, 2 );
```

**Internal mode (onelogin/php-saml):**

```php
add_filter( 'wp_saml_auth_option', function( $value, $option_name ) {
    $config = [
        'connection_type' => 'internal',
        'internal_config' => [
            'strict'  => true,
            'debug'   => false,
            'sp'      => [
                'entityId'                 => 'urn:' . parse_url( home_url(), PHP_URL_HOST ),
                'assertionConsumerService' => [
                    'url'     => wp_login_url(),
                    'binding' => 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST',
                ],
                'singleLogoutService'      => [
                    'url'     => wp_logout_url(),
                    'binding' => 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect',
                ],
                'NameIDFormat' => 'urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress',
                'x509cert'     => '',
                'privateKey'   => '',
            ],
            'idp' => [
                'entityId'            => '',   // IdP Issuer URI
                'singleSignOnService' => [
                    'url'     => '',           // IdP SSO endpoint
                    'binding' => 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect',
                ],
                'singleLogoutService' => [
                    'url'     => '',           // IdP SLO endpoint (optional)
                    'binding' => 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect',
                ],
                'x509cert' => '',              // IdP public certificate (no headers)
            ],
        ],
        'auto_provision'         => true,
        'permit_wp_login'        => true,
        'get_user_by'            => 'email',
        'user_login_attribute'   => 'uid',
        'user_email_attribute'   => 'mail',
        'display_name_attribute' => 'display_name',
        'first_name_attribute'   => 'first_name',
        'last_name_attribute'    => 'last_name',
        'default_role'           => get_option( 'default_role' ),
    ];
    return $config[ $option_name ] ?? $value;
}, 10, 2 );
```

## SimpleSAMLphp Installation

The plugin searches these paths in order for the SimpleSAMLphp autoloader:

1. Path returned by the `wp_saml_auth_ssp_autoloader` filter
2. Path set via the `simplesamlphp_autoload` option
3. Default search paths (filterable via `wp_saml_auth_simplesamlphp_path_array`):
   - `ABSPATH . 'simplesaml'`
   - `ABSPATH . 'private/simplesamlphp'`
   - `ABSPATH . 'simplesamlphp'`
   - `ABSPATH . 'vendor/simplesamlphp/simplesamlphp'` (Composer)
   - Plugin directory `simplesamlphp/` subdirectory

Within each path it checks for `vendor/autoload.php` (SSP 2.x) then `lib/_autoload.php` (SSP 1.x).

### SimpleSAMLphp Version Checks

The plugin checks the installed SimpleSAMLphp version and can show admin notices or block authentication:

| Option                              | Default  | Purpose                                                                |
| ----------------------------------- | -------- | ---------------------------------------------------------------------- |
| `min_simplesamlphp_version`         | `2.3.7`  | Versions below this show a warning notice but still authenticate       |
| `critical_simplesamlphp_version`    | `2.0.0`  | Versions below this show a critical error notice                       |
| `enforce_min_simplesamlphp_version` | `false`  | If true, authentication is blocked when below `critical_simplesamlphp_version` |

## Okta Configuration

These values apply when using `connection_type = 'internal'` (onelogin/php-saml). For SimpleSAMLphp mode, configure the IdP inside SimpleSAMLphp's own `metadata/` directory instead.

| Okta admin field                  | Plugin setting                                                   |
| --------------------------------- | ---------------------------------------------------------------- |
| Identity Provider issuer          | `idp.entityId`                                                   |
| IdP Single Sign-On URL            | `idp.singleSignOnService.url`                                    |
| IdP Single Logout URL             | `idp.singleLogoutService.url`                                    |
| X.509 Certificate (from metadata) | `idp.x509cert` (strip `-----BEGIN/END CERTIFICATE-----` headers) |
| (you set this) ACS URL            | `sp.assertionConsumerService.url` → `wp_login_url()`             |
| (you set this) SP Entity ID       | `sp.entityId` → e.g. `urn:yourdomain.com`                        |

Okta's default attribute names differ from the plugin's defaults. Either update the attribute mapping config or configure Okta to send attributes with these names:

| Okta attribute statement | Plugin default expects                          |
| ------------------------ | ----------------------------------------------- |
| `email` or `login`       | `mail` (change `user_email_attribute` to match) |
| `firstName`              | `first_name`                                    |
| `lastName`               | `last_name`                                     |

Okta sends unencrypted assertions by default — no special handling needed.

## Multisite

In multisite, when `wp_insert_user()` is called with a `role` parameter during auto-provisioning, WordPress automatically adds the user to the current site. Use the `wp_saml_auth_auto_add_to_blog` filter to prevent this:

```php
add_filter( 'wp_saml_auth_auto_add_to_blog', function( $auto_add, $blog_id, $user_args, $attributes ) {
    return false; // Create network user without adding to any site
}, 10, 4 );
```

## Key Filters & Actions

| Hook                                        | Purpose                                                                                                      |
| ------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| `wp_saml_auth_option`                       | Override any config option (disables admin UI when present)                                                  |
| `wp_saml_auth_ssp_autoloader`               | Return a direct path to the SimpleSAMLphp autoloader file                                                    |
| `wp_saml_auth_simplesamlphp_path_array`     | Filter the array of base paths searched for SimpleSAMLphp                                                    |
| `wp_saml_auth_internal_config`              | Customize the full `internal_config` array passed to `OneLogin\Saml2\Auth`                                   |
| `wp_saml_auth_pre_logout`                   | Fires before the user is logged out of SAML; use to run pre-logout cleanup                                   |
| `wp_saml_auth_internal_logout_args`         | Customize the `parameters`, `nameId`, and `sessionIndex` passed to internal-mode `logout()`                  |
| `wp_saml_auth_attributes`                   | Modify the attributes array after the SAML response, before user lookup                                      |
| `wp_saml_auth_patch_attributes`             | Fix oddly-shaped SAML responses (some providers return non-standard attribute structures)                    |
| `wp_saml_auth_pre_authentication`           | Runs after SAML validation, before WP login. Return `WP_Error` to reject. Use for group/role authorization. |
| `wp_saml_auth_insert_user`                  | Filter the user data array before `wp_insert_user()` on auto-provision                                       |
| `wp_saml_auth_auto_add_to_blog`             | Multisite: control whether a newly-provisioned user is added to the current site (default `true`)            |
| `wp_saml_auth_existing_user_authenticated`  | Fires after an existing user logs in via SSO                                                                 |
| `wp_saml_auth_new_user_authenticated`       | Fires after a new user is auto-provisioned and logged in                                                     |
| `wp_saml_auth_login_strings`                | Customize the title, button, and alt-title text shown on the login screen                                    |
| `wp_saml_auth_force_authn`                  | Return `true` to set `forceAuthn="true"` on the AuthnRequest (internal mode only)                           |
| `wp_saml_auth_login_parameters`             | Customize extra parameters passed to `$provider->login()` (internal mode only)                              |

## Feature Comparison vs. miniOrange Free

| Feature                          | WP SAML Auth                     | miniOrange Free                 |
| -------------------------------- | -------------------------------- | ------------------------------- |
| Okta / any SAML 2.0 IdP          | Yes                              | Yes                             |
| Auto-redirect (no WP login form) | Yes (`permit_wp_login => false`) | No                              |
| Single Logout (SLO)              | Yes                              | No                              |
| Attribute mapping                | Yes, all fields                  | Email + username only           |
| Auto user provisioning           | Yes                              | Yes                             |
| Admin UI                         | Yes                              | Yes                             |
| Upsell nags                      | None                             | Yes                             |
| License cost                     | Free, GPL                        | Free tier; $350/yr for Standard |
| Encrypted assertions             | Yes (internal mode via onelogin/php-saml) | No (hard exception in free) |

## Debugging Tips

- For SimpleSAMLphp mode: enable debug logging in SimpleSAMLphp's own `config/config.php` (`'logging.level' => SimpleSAML\Logger::DEBUG`).
- For internal mode: set `'debug' => true` in `internal_config` to have `onelogin/php-saml` write SAML messages to the PHP error log.
- Enable WordPress debug logging: `define( 'WP_DEBUG', true ); define( 'WP_DEBUG_LOG', true );`
- Check `wp-content/debug.log` for SAML validation errors (clock skew, certificate mismatch, audience restriction failures).
- The `wp_saml_auth_attributes` filter receives the full `$attributes` array — log it to inspect exactly what the IdP is sending.
- Use the IdP's SAML tracer / test tool to verify the `AuthnRequest` is well-formed before debugging the response side.
- Admin notices will appear on the settings page if SimpleSAMLphp is not found or its version is below the recommended threshold.
