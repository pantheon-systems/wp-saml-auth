<?php

/**
 * SAML 2.0 SP Remote Metadata for SimpleSAMLphp.
 * This file defines external SPs that this SimpleSAMLphp IdP knows about.
 * In this case, it defines the WordPress site (acting as an SP via wp-saml-auth)
 * to the SimpleSAMLphp instance (acting as an IdP).
 */

// Dynamically determine the SP's entityID and ACS URL based on the current host.
// Ensure $_SERVER['HTTP_HOST'] is correctly populated.
$current_host_with_port = isset($_SERVER['HTTP_HOST']) ? $_SERVER['HTTP_HOST'] : 'localhost'; // Fallback
$sp_hostname_part = explode(':', $current_host_with_port)[0];
$sp_entity_id = 'urn:' . $sp_hostname_part; // This should match the entityID of 'default-sp' in authsources.php
                                          // and the entityID used by wp-saml-auth.

$wp_base_url = 'https://' . $current_host_with_port;

$metadata[$sp_entity_id] = [
    // Assertion Consumer Service (ACS) URL for this SP.
    // This is where the IdP will send SAML assertions.
    // For wp-saml-auth, this is typically wp-login.php with a SAML action.
    'AssertionConsumerService' => [
        [
            'Binding' => 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST',
            'Location' => $wp_base_url . '/wp-login.php?saml_acs', // Default ACS for wp-saml-auth
        ],
    ],

    // Single Logout Service (SLS) URL for this SP.
    // This is where the IdP will send logout requests/responses.
    'SingleLogoutService' => [
        [
            'Binding' => 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect', // Or HTTP-POST
            'Location' => $wp_base_url . '/wp-login.php?saml_sls', // Default SLS for wp-saml-auth
        ],
    ],

    // NameID format the SP prefers or requires.
    // 'unspecified' is often a safe default.
    'NameIDFormat' => 'urn:oasis:names:tc:SAML:1.1:nameid-format:unspecified',

    // Optional: SP's public certificate if assertions need to be encrypted for this SP,
    // or if the IdP needs to verify signed requests from this SP.
    // If wp-saml-auth is configured to sign requests, its public key would go here.
    // 'certificate' => 'sp-public-key.crt', // Path relative to cert/ directory

    // Optional: Define which attributes this SP should receive.
    // This can also be controlled by IdP's authproc filters.
    // 'attributes' => ['uid', 'mail', 'displayName', 'eduPersonAffiliation'],
    
    // Optional: If NameID should be based on a specific attribute from the IdP.
    // 'simplesaml.nameidattribute' => 'uid',
];
