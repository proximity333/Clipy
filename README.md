<div align="center">
  <img src="./Resources/clipy_logo.png" width="400">
</div>

<br>

![CI](https://github.com/Clipy/Clipy/workflows/CI/badge.svg)
[![Release version](https://img.shields.io/github/release/Clipy/Clipy.svg)](https://github.com/Clipy/Clipy/releases/latest)
[![OpenCollective](https://opencollective.com/clipy/backers/badge.svg)](#backers)
[![OpenCollective](https://opencollective.com/clipy/sponsors/badge.svg)](#sponsors)

Clipy is a Clipboard extension app for macOS.

---

__Requirement__: macOS 10.10 Yosemite or higher

__Distribution Site__ : <https://clipy-app.com>

<img src="http://clipy-app.com/img/screenshot1.png" width="400">

### Development Environment
* macOS 10.15 Catalina
* Xcode 12.2
* Swift 5.3

### How to Build
0. Move to the project root directory
1. `bundle install --path=vendor/bundle && bundle exec pod install`
2. Open `Clipy.xcworkspace` on Xcode.
3. build.

### Release Checklist
1. Start from a clean, reviewed branch and install dependencies.

```sh
bundle install --path=vendor/bundle && bundle exec pod install
```

2. Update the app version in `Clipy/Supporting Files/Info.plist`.
Set both `CFBundleShortVersionString` and `CFBundleVersion` to the release version, for example `2.1.3`.

3. Run the release verification path before packaging.

```sh
bundle exec fastlane test
```

4. Commit the version bump and any release notes changes.

```sh
git add "Clipy/Supporting Files/Info.plist"
git commit -m "Bump version to 2.1.3"
```

5. Create the release tag before building the final artifact.

```sh
git tag v2.1.3
```

6. Build the release app into a disposable local output directory.

```sh
xcodebuild -workspace "Clipy.xcworkspace" -scheme "Clipy" -configuration Release -derivedDataPath build/DerivedData ENABLE_TESTABILITY=YES build
```

7. Package the built app for upload.

```sh
mkdir -p dist
ditto -c -k --sequesterRsrc --keepParent "build/DerivedData/Build/Products/Release/Clipy.app" "dist/Clipy-v2.1.3.zip"
```

Before uploading, verify the packaged app does not include test bundles or XCTest frameworks:

```sh
unzip -l "dist/Clipy-v2.1.3.zip" | grep -E "ClipyTests|XCTest|Testing\.framework|PlugIns"
```

This command should print nothing.

8. Push both the branch and the tag to GitHub.

```sh
git push origin HEAD
git push origin v2.1.3
```

9. Create the GitHub release and upload the packaged artifact.

```sh
gh release create v2.1.3 "dist/Clipy-v2.1.3.zip" --title "v2.1.3" --notes-file RELEASE_NOTES.md
```

If you do not keep release notes in a file, replace `--notes-file RELEASE_NOTES.md` with `--generate-notes` or `--notes "..."`.

10. Update the appcast (tags).

The release workflow does this for a pushed tag: it signs the DMG with the EdDSA key in `SPARKLE_PRIVATE_KEY`, adds an `<enclosure>` whose signature verifies against `SUPublicEDKey` in `Info.plist`, commits `appcast.xml` to `develop` (the app's `SUFeedURL`), and attaches the feed to the release. Do not edit `appcast.xml` by hand.

The private key is in the login keychain under `Proximity333/Clipy`; export it with `Pods/Sparkle/bin/generate_keys --account Proximity333/Clipy -x <file>` if the repository secret needs to be set again. Never commit it.

11. Clean local build outputs after the release is published.

```sh
rm -rf dist build
rm -rf ~/Library/Developer/Xcode/DerivedData/Clipy-*
```

12. Remove any locally copied or debug-built `Clipy.app` bundles that were left outside the standard install location.
This prevents Launchpad, Spotlight, and other app lists from showing multiple identical Clipy entries after repeated build and release runs.

Check common locations such as:

```text
~/Applications/
~/Desktop/
~/Downloads/
build/DerivedData/Build/Products/Release/
~/Library/Developer/Xcode/DerivedData/Clipy-*/Build/Products/
```

Keep only the one install you actually want to use, then empty Trash if you deleted extra app bundles.

### Contributing
1. Fork it ( https://github.com/Clipy/Clipy/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

### Localization Contributors
Clipy is looking for localization contributors.  
If you can contribute, please see [CONTRIBUTING.md](https://github.com/Clipy/Clipy/blob/master/.github/CONTRIBUTING.md)

### Distribution
If you distribute derived work, especially in the Mac App Store, I ask you to follow two rules:

1. Don't use `Clipy` and `ClipMenu` as your product name.
2. Follow the MIT license terms.

Thank you for your cooperation.

### Backers

Support us with a monthly donation and help us continue our activities. [[Become a backer](https://opencollective.com/clipy#backer)]

<a href="https://opencollective.com/clipy/backer/0/website" target="_blank"><img src="https://opencollective.com/clipy/backer/0/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/1/website" target="_blank"><img src="https://opencollective.com/clipy/backer/1/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/2/website" target="_blank"><img src="https://opencollective.com/clipy/backer/2/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/3/website" target="_blank"><img src="https://opencollective.com/clipy/backer/3/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/4/website" target="_blank"><img src="https://opencollective.com/clipy/backer/4/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/5/website" target="_blank"><img src="https://opencollective.com/clipy/backer/5/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/6/website" target="_blank"><img src="https://opencollective.com/clipy/backer/6/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/7/website" target="_blank"><img src="https://opencollective.com/clipy/backer/7/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/8/website" target="_blank"><img src="https://opencollective.com/clipy/backer/8/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/9/website" target="_blank"><img src="https://opencollective.com/clipy/backer/9/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/10/website" target="_blank"><img src="https://opencollective.com/clipy/backer/10/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/11/website" target="_blank"><img src="https://opencollective.com/clipy/backer/11/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/12/website" target="_blank"><img src="https://opencollective.com/clipy/backer/12/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/13/website" target="_blank"><img src="https://opencollective.com/clipy/backer/13/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/14/website" target="_blank"><img src="https://opencollective.com/clipy/backer/14/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/15/website" target="_blank"><img src="https://opencollective.com/clipy/backer/15/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/16/website" target="_blank"><img src="https://opencollective.com/clipy/backer/16/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/17/website" target="_blank"><img src="https://opencollective.com/clipy/backer/17/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/18/website" target="_blank"><img src="https://opencollective.com/clipy/backer/18/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/19/website" target="_blank"><img src="https://opencollective.com/clipy/backer/19/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/20/website" target="_blank"><img src="https://opencollective.com/clipy/backer/20/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/21/website" target="_blank"><img src="https://opencollective.com/clipy/backer/21/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/22/website" target="_blank"><img src="https://opencollective.com/clipy/backer/22/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/23/website" target="_blank"><img src="https://opencollective.com/clipy/backer/23/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/24/website" target="_blank"><img src="https://opencollective.com/clipy/backer/24/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/25/website" target="_blank"><img src="https://opencollective.com/clipy/backer/25/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/26/website" target="_blank"><img src="https://opencollective.com/clipy/backer/26/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/27/website" target="_blank"><img src="https://opencollective.com/clipy/backer/27/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/28/website" target="_blank"><img src="https://opencollective.com/clipy/backer/28/avatar.svg"></a>
<a href="https://opencollective.com/clipy/backer/29/website" target="_blank"><img src="https://opencollective.com/clipy/backer/29/avatar.svg"></a>

### Sponsors

Become a sponsor and get your logo on our README on Github with a link to your site. [[Become a sponsor](https://opencollective.com/clipy#sponsor)]

<a href="https://opencollective.com/clipy/sponsor/0/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/0/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/1/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/1/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/2/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/2/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/3/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/3/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/4/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/4/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/5/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/5/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/6/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/6/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/7/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/7/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/8/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/8/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/9/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/9/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/10/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/10/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/11/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/11/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/12/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/12/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/13/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/13/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/14/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/14/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/15/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/15/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/16/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/16/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/17/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/17/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/18/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/18/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/19/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/19/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/20/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/20/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/21/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/21/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/22/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/22/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/23/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/23/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/24/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/24/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/25/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/25/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/26/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/26/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/27/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/27/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/28/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/28/avatar.svg"></a>
<a href="https://opencollective.com/clipy/sponsor/29/website" target="_blank"><img src="https://opencollective.com/clipy/sponsor/29/avatar.svg"></a>

### Licence
Clipy is available under the MIT license. See the LICENSE file for more info.

Icons are copyrighted by their respective authors.

### Special Thanks
__Thank you for [@naotaka](https://github.com/naotaka) who have published [ClipMenu](https://github.com/naotaka/ClipMenu) as OSS.__
