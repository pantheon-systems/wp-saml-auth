# Contributing

The best way to contribute to the development of this plugin is by participating on the GitHub project:

https://github.com/pantheon-systems/wp-saml-auth

Pull requests and issues are welcome!

## Workflow

Development and releases are structured around two branches, `main` and `release`.
The `main` branch is the default branch for the repository, and is the source and destination for feature branches.

We prefer to squash commits (i.e., avoid merge PRs) from a feature branch into `main` when merging, and to include the PR number in the commit message. PRs to `main` should also include any relevant updates to the changelog in `readme.txt` and `README.md`. For example, if a feature constitutes a minor or major version bump, that version update should be discussed and made as part of approving and merging the feature into `main`.

`main` should be stable and usable, though possibly a few commits ahead of the public release on wp.org.

The `release` branch matches the latest stable release deployed to [wp.org](https://wordpress.org/plugins/wp-saml-auth/).

## Testing

Tests run on GitHub Actions:

* **PHPUnit** runs the unit test suite, which mocks interactions with SimpleSAMLphp.
* **Behat** runs the integration test suite against a Pantheon site, to ensure the plugin's compatibility with the Pantheon platform. This includes configuring a fully-functional instance of SimpleSAMLphp.

Both of these test suites can be run locally, with a varying amount of setup.

PHPUnit requires the [WordPress PHPUnit test suite](https://make.wordpress.org/core/handbook/testing/automated-testing/phpunit/), and access to a database with name `wordpress_test`. If you haven't already configured the test suite locally, you can run `bash bin/install-wp-tests.sh wordpress_test root '' localhost`.

Behat requires a Pantheon site. Once you've created the site, you'll need [install Terminus](https://github.com/pantheon-systems/terminus#installation), and set the `TERMINUS_TOKEN`, `TERMINUS_SITE`, and `TERMINUS_ENV` environment variables. Then, you can run `./bin/behat-prepare.sh` to prepare the site for the test suite.

## Release Process

1. Merge your feature branch into `main` with a PR. This PR should include any necessary updates to the changelog in `readme.txt` and `README.md`. Features should be squash merged.
1. When changes are pushed to `main`, the `release-pr.yml` workflow automatically creates a draft PR (`release-X.Y.Z` branch) targeting the `release` branch. This PR removes the `-dev` suffix from the version number in `README.md`, `readme.txt`, and `wp-saml-auth.php`, and adds the release date to the changelog.
1. Review the auto-generated release PR. Verify that the version numbers and changelog entries are correct.
1. After all tests pass and you have received approval from a CODEOWNER (including resolving any merge conflicts), merge the PR into `release`. Use a **merge commit**, do not rebase or squash. If the GitHub UI doesn't offer a "Merge commit" option (only showing "Squash and merge" or "Rebase and merge"), merge from the terminal instead:
    ```
    git checkout release
    git merge release-X.Y.Z
    git push origin release
    ```
1. After merging to the `release` branch, a draft Release will be automatically created by the `build-tag-release` workflow. This draft release will be automatically pre-filled with release notes.
1. Confirm that the necessary assets are present in the newly created tag, and test on a WP install if desired.
1. Review the release notes, making any necessary changes, and publish the release.
1. Wait for the `wordpress-plugin-deploy` workflow to finish deploying to the WordPress.org plugin repository.
1. If all goes well, users with SVN commit access for that plugin will receive an email with a diff of the changes.
1. Check WordPress.org: Ensure that the changes are live on the plugin repository. This may take a few minutes.
1. Following the release, reconcile branches and prepare the next dev version:
    * Merge `release` back into `main` to synchronize commit history (this prevents commit hash divergence in future releases):
      ```
      git checkout main
      git pull origin main
      git merge origin/release
      git push origin main
      ```
    * Update the version number in `README.md`, `readme.txt`, and `wp-saml-auth.php`, incrementing by one patch version and adding the `-dev` flag (e.g. after releasing `1.2.3`, the new version will be `1.2.4-dev`).
    * Add a new `** X.Y.Z-dev **` heading to the changelog.
    * Commit and push:
      ```
      git add -A .
      git commit -m "Prepare X.Y.Z-dev"
      git checkout -b prepare-XYZ-dev
      git push origin prepare-XYZ-dev
      ```
    * Create a pull request from `prepare-XYZ-dev` to `main` to trigger all required status checks.
    * Once all tests pass, merge the PR into `main`.
