<?php
require __DIR__ . '/../../_include.php';

use SimpleSAML\Auth\State;
use SimpleSAML\Utils\HTTP;

$stateId = $_GET['AuthState'] ?? null;
if (!$stateId) {
    die("Missing AuthState");
}

$state = State::loadState($stateId, 'SimpleSAML_Auth_State');
echo '<pre>';
print_r($state);
echo '</pre>';
