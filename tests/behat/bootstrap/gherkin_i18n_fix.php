<?php
// tests/behat/bootstrap/gherkin_i18n_fix.php

$vendorDir = __DIR__ . '/../../../vendor'; // Path relative to this bootstrap file
$gherkinDir = $vendorDir . '/behat/gherkin';

// Add the gherkin directory to the include path
$newIncludePath = get_include_path() . PATH_SEPARATOR . $gherkinDir;
set_include_path($newIncludePath);

?>
