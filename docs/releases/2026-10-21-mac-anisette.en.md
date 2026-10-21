# AltServer-mac / AltStore-mac-anisette (Unofficial Build)

[简体中文](2026-10-21-mac-anisette.md) | [English](2026-10-21-mac-anisette.en.md)

This community build is intended to investigate and mitigate `-80045` and Apple GrandSlam HTTP 503 errors. It is not an official AltStore release. It includes AltServer for macOS and an AltStore IPA with on-device remote refresh support.

## Downloads

- **`AltServer-mac.zip`**: Extracts to `AltServer-mac.app`. AltServer 1.8 (98), a Universal build for Apple Silicon and Intel Macs. Ad-hoc signed, not notarized, and not signed with a personal Apple developer certificate.
- **`AltStore-mac-anisette.ipa`**: AltStore 2.3 (73), built in Release configuration. It contains no personal signing certificate or provisioning profile. AltServer signs it with your Apple ID during installation.
- **`SHA256SUMS.txt`**: SHA-256 checksums for both packages.

The apps declare minimum versions of macOS 12.0 and iOS 17.4. This round of testing used macOS 15.7.2 and an iPhone 15 running iOS 26.6.1. Intel Macs, other OS versions, and the macOS 27 code path were not tested on hardware in this round.

## Upstream PRs and additional changes

The base is the official AltStore `classic` branch at `fafd76ee1a8a19c723146de278660aacce9ded5d`.

- [AltStore #1835](https://github.com/altstoreio/AltStore/pull/1835): Integrates its on-device Windows Anisette, authentication, and resynchronization changes.
- [AltSign #61](https://github.com/rileytestut/AltSign/pull/61): Uses the Anisette provider's client identity and User-Agent, handles HTTP errors, and supports Anisette resync. Its base includes [AltSign #59](https://github.com/rileytestut/AltSign/pull/59), which handles 2FA codes that Apple sends automatically.
- [AltStore #1838](https://github.com/altstoreio/AltStore/pull/1838): Removes leftover AltSign-Dynamic product dependencies from AltServer and AltJIT to address the related OpenSSL linking failures.
- The remote Anisette client for macOS 27 and later follows the approach in [AltStore #1834](https://github.com/altstoreio/AltStore/pull/1834), with adaptations in this fork. That PR was not merged verbatim. Earlier macOS versions retain the official native AOSKit/Mail path.

This build adds the following on top:

1. Following [iLoader 2.3.9](https://github.com/nab138/iloader/releases/tag/v2.3.9) and its [server directory](https://github.com/nab138/iloader/blob/main/src/pages/Settings.tsx), it puts `https://new.ani.sidestore.io` and `https://mac-ani.jkcoxson.com` ahead of the two previously added Windows servers. This applies to the on-device server directory and automatic candidate order, and to the default remote list on macOS 27 and later.
2. An updated server selection UI shows the selected server. When the device connection is Connected, it can display the device and platform fields returned by that server, such as MacBookPro / Mac OS X or PC / Windows. These are advertised identity fields, not an audit of the server's underlying implementation.
3. Provisioning state is bound to the server URL, client_info, and user_agent. The client identity is kept fixed throughout each SRP authentication flow so refreshing data cannot silently switch device identities.
4. App Group database migration is skipped when no shared container is available, avoiding the related startup crash. Authentication failures retain a small amount of metadata, including the stage, response type, and response size.

Integrating these PRs into this fork does not mean they have been merged upstream. No additional general-purpose HTTP 503 retry loop or HTML error viewer is included.

## Current HTTP 503 status

**The earlier Windows-based changes still produced intermittent HTTP 503 errors. After adding and switching to the iLoader Mac servers above, the 503 blocker was cleared in this local test run, and on-device remote refresh completed successfully.**

This is a result from the current test environment, not a permanent or universal fix for 503. Apple authentication and third-party Anisette services can still fail, and the error may recur with different accounts, networks, or service conditions. Distinguish a 502/503 from an Anisette server from an authentication 503 returned by `gsa.apple.com`.

On-device remote refresh and installation from a computer use separate paths: **AltServer on macOS 15 still uses native Anisette. Selecting a Mac server in the phone's settings does not change that computer-side path.** The new list order also does not override a server selection that the user has already saved.

## Installation

### 1. Install AltServer-mac

1. Download the ZIP, IPA, and checksum file from this release. Quit any other running AltServer instance.
2. Extract `AltServer-mac.zip` and move `AltServer-mac.app` to `/Applications`.
3. If macOS blocks the downloaded app because of quarantine, verify the download source, then run:

   ```sh
   xattr -dr com.apple.quarantine /Applications/AltServer-mac.app
   ```

4. Open the app and confirm that the AltServer icon appears in the menu bar. This build is ad-hoc signed and not notarized. Do not replace it using the app's official automatic update mechanism.
5. Connect your iPhone with a USB cable, unlock it, and trust the computer when prompted on the phone or in Finder.

### 2. Install the AltStore IPA attached to this release

1. **Hold Option, then click the AltServer menu bar icon.** Choose **Sideload .ipa… → your device**.
2. In the file picker, select **`AltStore-mac-anisette.ipa`** downloaded from this release.
3. Enter your Apple ID and password and complete trusted-device 2FA when prompted. SMS 2FA compatibility issues have been reported in the related community approaches; its reliability has not been verified in this build.
4. If iOS asks you to trust the developer, trust your own developer identity under **Settings → General → VPN & Device Management**.
5. If iOS requires Developer Mode, enable it under **Settings → Privacy & Security → Developer Mode**, restart, and confirm. Then open AltStore.

**Do not use the ordinary “Install AltStore…” entry to install this modified IPA. That entry downloads AltStore according to the official configuration; it does not automatically use the attachment from this release.** Apple's free-account limits still apply, including app and App ID limits and the seven-day expiration period.

### 3. Set up on-device remote refresh

1. Open **Settings → Remote AltServer** in AltStore and follow the setup wizard.
2. On systems that require pairing through a computer, keep the USB cable connected and AltServer running. Tap **Pair with AltServer** and confirm trust when prompted. On iOS 27, the wizard may instead show **Pair in Settings / Start Pairing**; follow the instructions shown.
3. Install and open [LocalDevVPN](https://apps.apple.com/app/id6755608044), allow it to add a VPN configuration, and connect it. Keep Wi-Fi enabled, then return to AltStore to finish setup.
4. In the Remote AltServer server list, explicitly select **SideStore (Mac ADI)** (`new.ani.sidestore.io`) or **jkcoxson (Mac ADI)** (`mac-ani.jkcoxson.com`). The successful refresh in this test run used the latter.
5. Confirm that remote mode is enabled and the selected server is displayed. When Connected, check the Device / Platform fields. Connected only indicates that the local device connection is reachable; it does not guarantee successful Apple authentication.
6. Refresh AltStore or another app under **My Apps**. Verify that the expiration time actually changes. Seeing “7 days” alone is not enough to confirm that a new refresh succeeded.
7. After initial pairing, on-device remote refresh does not require the computer to stay running. It still needs Wi-Fi, LocalDevVPN, and access to the Anisette and Apple services.

### 4. Updating an existing installation

**After installing AltStore over an existing copy from a computer, we recommend resetting Remote AltServer and pairing again. You do not need to uninstall AltStore or your other installed apps first.**

1. Reset the configuration under **Settings → Remote AltServer → Reset Remote AltServer**.
2. Repeat the pairing and LocalDevVPN setup steps above.
3. Select one of the Mac Anisette servers again, then test a refresh.

Installing from a computer generates a new embedded pairing file, while the phone may retain its existing pairing file in Keychain. If you encounter `OnDeviceError 2` / `Connection reset by peer`, a mismatch between old and new pairing identities is one possible cause to investigate. This is separate from Apple's HTTP 503 errors. Resetting is a workaround, not an implemented automatic migration fix; this build retains the official pairing-file import policy.

## Custom servers and troubleshooting

- On the phone, the user's selected server is tried first. The candidate list is used if fetching Anisette data fails. An Apple authentication 503 does not automatically trigger rotation through every server.
- To configure a custom computer-side remote Anisette server on macOS 27 or later, quit AltServer, run the following, and reopen it:

  ```sh
  defaults write com.rileytestut.AltServer AnisetteServerURL https://mac-ani.jkcoxson.com
  ```

  To restore the default list:

  ```sh
  defaults delete com.rileytestut.AltServer AnisetteServerURL
  ```

  This setting does not apply to the native path on earlier macOS versions and does not change the server selected on the phone.
- No Anisette server is bundled with these apps; they depend on community services. In the current implementation, Apple ID passwords and verification codes are submitted to Apple. The Anisette service participates in device identity provisioning and data generation.
- If you encounter a 503, record whether it occurred during `init`, `complete`, or `apptokens`, along with the server address, OS version, and app version. Try again later rather than making many rapid attempts. Do not publish passwords, verification codes, pairing files, adi.pb, or authentication tokens.

## Verification and source

Run this in the directory containing both packages and the checksum file:

```sh
shasum -a 256 -c SHA256SUMS.txt
```

The source is pinned by this release tag. The AltSign submodule points to [`020ddb5691ffb9b75dfdd92b83a6809bbfdd1d5b`](https://github.com/liuzhe1117/AltSign/commit/020ddb5691ffb9b75dfdd92b83a6809bbfdd1d5b).

```sh
git clone --recurse-submodules --branch v1.8-mac-anisette-unofficial-20261021 https://github.com/liuzhe1117/AltStore.git
cd AltStore
pod install
xcodebuild -workspace AltStore.xcworkspace -scheme AltServer -configuration Release -sdk macosx -destination 'platform=macOS' CURRENT_PROJECT_VERSION=98 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
xcodebuild -workspace AltStore.xcworkspace -scheme AltStore -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' CURRENT_PROJECT_VERSION=73 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

This round used Xcode 26.3.0. These commands produce build products. The macOS distribution app is additionally ad-hoc signed; the iOS product is packaged as an IPA containing `Payload/AltStore.app` and signed again by the installation tool.

Thanks to the authors of the PRs above and the maintainers of iLoader / isideload, SideStore, and the Anisette services. The licenses and copyright notices of the original projects and dependencies continue to apply.
