fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios release

```sh
[bundle exec] fastlane ios release
```

Build and upload a new build to TestFlight

### ios dist_cert

```sh
[bundle exec] fastlane ios dist_cert
```

Create (or reuse) an Apple Distribution certificate in this keychain

### ios whats_new

```sh
[bundle exec] fastlane ios whats_new
```

Upload the What's New text for the current version (nothing else)

### ios screenshots

```sh
[bundle exec] fastlane ios screenshots
```

Upload the current App Store screenshots (no binary, no metadata)

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
