<?php

namespace PantheonSystems\WPSamlAuth\Behat;

use Behat\Gherkin\Keywords\CachedArrayKeywords as BaseCachedArrayKeywords;
use ReflectionClass;
use RuntimeException;

class SafePathCachedArrayKeywords extends BaseCachedArrayKeywords
{
    public static function withDefaultKeywords(): self
    {
        // Determine the path to i18n.php robustly by finding the base of the behat/gherkin package
        $reflector = new ReflectionClass(BaseCachedArrayKeywords::class);
        // $parentFile should be .../vendor/behat/gherkin/src/Keywords/CachedArrayKeywords.php
        $parentFile = $reflector->getFileName();

        // dirname($parentFile, 3) should resolve to .../vendor/behat/gherkin/
        $gherkinPackageBaseDir = dirname($parentFile, 3);
        $i18nPath = $gherkinPackageBaseDir . '/i18n.php';

        $realI18nPath = realpath($i18nPath);

        if ($realI18nPath === false) {
            // This should ideally not happen if the package is intact and our path logic is correct
            throw new RuntimeException("SafePathCachedArrayKeywords: realpath failed for calculated i18n path: " . $i18nPath . ". Parent file was: " . $parentFile);
        }

        // The constructor of the parent (CachedArrayKeywords) expects the path.
        // It will then do `parent::__construct(require $realI18nPath);`
        return new self($realI18nPath);
    }
}
