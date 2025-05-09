# Contributing

The best way to contribute to the development of this plugin is by participating on the GitHub project:

https://github.com/pantheon-systems/wp-saml-auth

Pull requests and issues are welcome!

## Workflow

The `develop` branch is the development branch which means it contains the next version to be released. `master` contains the corresponding stable development version. Always work on the `develop` branch and open up PRs against `develop`.

We prefer to squash commits (i.e. avoid merge PRs) from a feature branch into `develop` when merging, and to include the PR # in the commit message. PRs to `develop` should also include any relevent updates to the changelog in readme.txt. For example, if a feature constitutes a minor or major version bump, that version update should be discussed and made as part of approving and merging the feature into `develop`. We do not update the README changelogs for development or process related PRs (i.e. dev-only dependencies, or changes to CI patterns unrelated to new features).

## Testing

You may notice there are two sets of tests running, on two different services:

* Travis CI runs the [PHPUnit](https://phpunit.de/) test suite, which mocks interactions with SimpleSAMLphp.
* Circle CI runs the [Behat](http://behat.org/) test suite against a Pantheon site, to ensure the plugin's compatibility with the Pantheon platform. This includes configuring a fully-functional instance of SimpleSAMLphp.

Both of these test suites can be run locally, with a varying amount of setup.

PHPUnit requires the [WordPress PHPUnit test suite](https://make.wordpress.org/core/handbook/testing/automated-testing/phpunit/), and access to a database with name `wordpress_test`. If you haven't already configured the test suite locally, you can run `bash bin/install-wp-tests.sh wordpress_test root '' localhost`.

Behat requires a Pantheon site. Once you've created the site, you'll need [install Terminus](https://github.com/pantheon-systems/terminus#installation), and set the `TERMINUS_TOKEN`, `TERMINUS_SITE`, and `TERMINUS_ENV` environment variables. Then, you can run `./bin/behat-prepare.sh` to prepare the site for the test suite.

## Release Process

1. From `develop`, checkout a new branch `release_X.Y.Z`.
1. Make a release commit:
    * Drop the `-dev` from the version number in `README.md`, `readme.txt`, and `wp-saml-auth.php`.
    * Commit these changes with the message `Release X.Y.Z`
    * Push the release branch up.
1. Open a Pull Request to merge `release_X.Y.Z` into `main`. Your PR should consist of all commits to `develop` since the last release, and one commit to update the version number. The PR name should also be `Release X.Y.Z`.
1. After all tests pass and you have received approval from a [CODEOWNER](./CODEOWNERS), merge the PR into `master`. A merge commit is preferred in this case. _Never_ squash to `master`.
1. CI will create a tag, commit the assets to it, and draft a [new release](https://github.com/pantheon-systems/wp-saml-auth/releases).
1. Open the release draft, review the changelog, assert the assets (vendor) have been added, and publish the release when ready.
1. Wait for the [_Release wp-saml-auth plugin to wp.org_ action](https://github.com/pantheon-systems/wp-saml-auth/actions/workflows/wordpress-plugin-deploy.yml) to finish deploying to the WordPress.org plugin repository. If all goes well, users with SVN commit access for that plugin will receive an emailed diff of changes.
1. Check WordPress.org: Ensure that the changes are live on [the plugin repository](https://wordpress.org/plugins/wp-saml-auth/). This may take a few minutes.
1. Following the release, prepare the next dev version with the following steps:
    * `git checkout develop`
    * `git rebase master`
    * Update the version number in all locations, incrementing the version by one patch version, and add the `-dev` flag (e.g. after releasing `1.2.3`, the new verison will be `1.2.4-dev`)
    * Add a new `** X.Y.X-dev **` heading to the changelogs
    * `git add -A .`
    * `git commit -m "Prepare X.Y.X-dev"`
    * `git push origin develop`
