<?php

add_action( 'wp_enqueue_scripts', 'samltheme_parent_theme_enqueue_styles' );

function samltheme_parent_theme_enqueue_styles() {
    wp_enqueue_style( 'theme-style', get_template_directory_uri() . '/style.css' );
    wp_enqueue_style( 'samltheme-style',
        get_stylesheet_directory_uri() . '/style.css',
        array( 'theme-style' )
    );

}

add_filter( 'wp_saml_auth_option', function( $value, $option_name ){
    if ( 'connection_type' === $option_name ) {
        return 'internal';
    }
    if ( 'internal_config' === $option_name ) {
        $value['idp']['entityId'] = home_url( '/simplesaml' );
        $value['idp']['singleSignOnService']['url'] = home_url( '/simplesaml/saml2/idp/SSOService.php' );
        $value['idp']['x509cert'] = file_get_contents( ABSPATH . '/simplesaml/cert/saml.crt' );
        $value['idp']['singleLogoutService']['url'] = home_url( '/simplesaml/saml2/idp/SingleLogoutService.php' );
        return $value;
    }
    // From https://commons.lbl.gov/display/IDMgmt/Attribute+Definitions#AttributeDefinitions-uiduid
    if ( 'user_login_attribute' === $option_name ) {
        return 'uid';
    }
    if ( 'user_email_attribute' === $option_name ) {
        return 'mail';
    }
    if ( 'permit_wp_login' === $option_name ) {
        return false;
    }
    return $value;
}, 11, 2 );
