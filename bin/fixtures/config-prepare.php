<?php
// This file is wp-content/mu-plugins/config-prepare.php

// Ensure WordPress ABSPATH constant is available.
if ( defined( 'ABSPATH' ) ) {
    // ABSPATH usually has a trailing slash, e.g., /var/www/html/
    // We want [WP_ROOT]/simplesaml/config/
    // So, ABSPATH . 'simplesaml/config/' is correct if simplesaml is at the root.
    $ssp_config_path = ABSPATH . 'simplesaml/config/';

    // Define the SIMPLESAMLPHP_CONFIG_DIR PHP constant.
    // SimpleSAMLphp's Configuration::getInstance() will use this if defined,
    // allowing it to find its config files (config.php, authsources.php, etc.).
    if ( ! defined( 'SIMPLESAMLPHP_CONFIG_DIR' ) ) {
        define( 'SIMPLESAMLPHP_CONFIG_DIR', $ssp_config_path );
    }
} else {
    // This should ideally not happen in a WordPress context where MU plugins are loaded.
    error_log('WP SAML Auth (config-prepare.php): CRITICAL - ABSPATH not defined. Cannot define SIMPLESAMLPHP_CONFIG_DIR. SimpleSAMLphp will likely fail.');
}
