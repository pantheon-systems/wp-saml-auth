<?php
require __DIR__ . '/_include.php';

use SimpleSAML\Auth\State;

$authState = $_GET['AuthState'] ?? null;

if (!$authState) {
    echo "Missing AuthState.";
    exit;
}

try {
    $state = State::loadState($authState, 'SimpleSAML_Auth_State');
    echo "<pre>";
    print_r($state);
    echo "</pre>";
} catch (Throwable $e) {
    echo "Error loading AuthState: " . $e->getMessage();
}
