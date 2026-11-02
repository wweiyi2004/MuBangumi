# MuBangumi maintenance rules

- Preserve existing worktree changes and local credentials/data. Never include runtime databases, WebView profiles, OAuth files, models or release symbols in commits or packages.
- Use the versions in `tool/toolchain.json`. `tool/toolchain.ps1` resolves project-local SDK paths; do not silently upgrade the global SDK or change the Shorebird baseline.
- Keep API credentials, website sessions and Banjian participation credentials as separate domains with explicit account ownership.
- Community P1 writes share `CommunityWriteClient`; test old responses after account changes for every affected verb. Never blindly replay an uncertain private-message POST.
- Keep core/application code independent of screens. Run the architectural check after changing dependencies.
- Use focused regressions while editing, then `tool/verify_all.ps1` (Full for native/release changes). Its JSON result records failures and deferred platforms. Never report unrun device/cloud checks as passed.
- Authenticated live message/post tests need explicit authorization and dedicated test recipients/groups. Normal tests use synthetic data.
- Native Android prototype is frozen. Python recommendation/semantic tools are research modules, not shipped client inference.
- Release provenance contains source/tool/lock/artifact identifiers, never credential values. Do not publish from a dirty worktree or invent device acceptance records.

## Standard build and verification flow

1. Work from the repository root and use the pinned tools. Do not substitute a global Flutter, Dart, Node, or Python installation.

   ```powershell
   . ./tool/toolchain.ps1
   Invoke-MuFlutter -Arguments @('pub','get','--enforce-lockfile')
   ```

2. While editing, run focused regressions for every affected behavior. Before delivery, run Quick verification; run Full verification for native, dependency, build, or release changes.

   ```powershell
   ./tool/verify_all.ps1 -Mode Quick
   ./tool/verify_all.ps1 -Mode Full -WindowsSmoke
   ./tool/verify_all.ps1 -Mode Full -DeviceId <dedicated-android-device-or-emulator-id>
   ```

   Use the JSON under `.dart_tool/verification/<run>/results.json` as the result. Do not edit source during a verification run: its source fingerprint must match the eventual build. Quick is not a substitute for Full release evidence. Windows smoke, Android device smoke, iOS CI, and manual account/device acceptance are separate kinds of evidence.

3. For a local ordinary Release build, use the existing entry point rather than assembling Flutter arguments manually.

   ```powershell
   ./tool/build_release.ps1 -Target apk -UniversalApk
   ./tool/build_release.ps1 -Target windows
   # Use -Target appbundle instead of apk when an AAB is required.
   ```

   `config/oauth.local.json` and Android release signing must already be configured through their ignored local files; never print or copy their secret values into logs. `-AllowDirty` is permitted only for a local, non-publication ordinary build. Direct Flutter build/run commands must pass the same `MUBANGUMI_FEEDBACK_URL` dart-define used by `tool/build_release.ps1`; do not create a second feedback endpoint configuration.

4. For a Windows distribution package, first produce a clean, verified ordinary build and locate its `provenance.json`, then package and independently verify the archive. Local unverified or `-AllowDirty` builds are not publication candidates.

   ```powershell
   ./tool/package_windows_release.ps1 -Version <x.y.z> -BuildNumber <N> `
     -ProvenanceManifest <windows-provenance.json>
   ./tool/verify_windows_package.ps1 -ArchivePath <dist/MuBangumi-x.y.z-buildN-windows-x64.zip>
   ```

A successful build or dry-run is not publication. Do not commit, push, upload release assets, create a Shorebird release, or push a patch unless the maintainer has requested that specific action.

## Choose a full release or a hot update

- Use a full package for new versions, accumulated features, native code, Android permissions/signing, plugin or other native dependency changes, assets, Flutter/engine changes, or a new Shorebird baseline.
- Use Shorebird Patch only for compatible Dart changes on an exact, already released Shorebird baseline. Do not include native, plugin, permission, asset, engine, or baseline changes and do not override its version/build number.
- Ordinary Flutter packages do not contain the Shorebird updater and cannot receive patches. Users on another Shorebird baseline also need the corresponding full package.
- Never silently change the existing Shorebird baseline or publish a patch to see whether it works. Use `-DryRun` for compilation checks and perform real uploads only after the release gates below pass.

## Standard full-version release flow

1. Finalize the release scope. Set a previously unused `version: x.y.z+build` in `pubspec.yaml`, move the relevant `CHANGELOG.md` entries into that version, and write `docs/releases/<x.y.z>.md` with upgrade instructions and explicit verification gaps. Use a unique Git tag `vx.y.z+build`; never replace an already published asset with different bytes.
2. Review and commit the exact source to publish, then ensure the worktree is clean. Obtain its identity with:

   ```powershell
   python tool/release_provenance.py identity --root .
   ```

3. Run Full verification on that unchanged source. For device acceptance, copy `tool/qa/acceptance.example.json` into an ignored `.dart_tool` file and record only checks actually performed. Shorebird uploads require both a passing Full report and a complete platform acceptance report from the last 7 days, with matching source fingerprints and version. Ordinary releases may proceed only with the maintainer's explicit acceptance of any remaining manual gaps, which must be documented rather than marked as passed.
4. Build ordinary full packages with the release verification report. Add `-AcceptanceReport` when a complete report is available.

   ```powershell
   ./tool/build_release.ps1 -Target apk -UniversalApk `
     -GiteeRepository 'wweiyi/mu-bangumi' `
     -VerificationReport <full-results.json>
   ./tool/build_release.ps1 -Target windows `
     -GiteeRepository 'wweiyi/mu-bangumi' `
     -VerificationReport <full-results.json>
   ```

   To create a new Shorebird baseline instead, add `-Shorebird` and supply both reports. This is a real remote Shorebird release, not merely a local build.

   ```powershell
   ./tool/build_release.ps1 -Target apk -Shorebird `
     -VerificationReport <full-results.json> `
     -AcceptanceReport <android-acceptance.json>
   ./tool/build_release.ps1 -Target windows -Shorebird `
     -VerificationReport <full-results.json> `
     -AcceptanceReport <windows-acceptance.json>
   ```

   Use `-Target appbundle` for an AAB. Add `-DryRun` to a Shorebird command for a non-uploading build check. Build each version once and distribute the same bytes through every mirror. After a real Shorebird release, verify the server release ID and record its receipt before calling the baseline verified:

   ```powershell
   python tool/release_provenance.py release-receipt --root . `
     --manifest <shorebird-release-provenance.json> `
     --release-id <real-server-id> --version <x.y.z+N>
   ```

5. Package Windows with its exact build provenance and stage assets using the update system's names:

   ```powershell
   ./tool/package_windows_release.ps1 -Version <x.y.z> -BuildNumber <N> `
     -ProvenanceManifest <windows-provenance.json>
   ```

   ```text
   MuBangumi-x.y.z-buildN-android.apk
   MuBangumi-x.y.z-buildN-android-arm64-v8a.apk
   MuBangumi-x.y.z-buildN-android-armeabi-v7a.apk
   MuBangumi-x.y.z-buildN-android-x86_64.apk
   MuBangumi-x.y.z-buildN-windows-x64.zip
   ```

   The packaging script writes the final Windows filename directly and adds the ZIP to the same provenance record. Keep original build outputs, hashes, and provenance associated with every distributed file.
6. Verify final artifact version/build, Android signature and upgrade path, Windows ZIP contents and clean-directory startup, expected feedback configuration, and SHA-256 for every asset. Test the actual final packages, not only a Debug build. Back up `release-symbols/` and provenance privately; never attach symbols, OAuth files, signing keys, databases, WebView profiles, or local logs to the public release.
7. Create a GitHub Draft Release with all assets and release notes, ensure every downloadable asset has a SHA-256 digest, then publish it only after the draft is complete. Let the Gitee workflow mirror that same release, or use the explicit maintainer-controlled entry point:

   ```powershell
   ./tool/publish_gitee.ps1 -Tag 'vx.y.z+build' -DryRun
   ./tool/publish_gitee.ps1 -Tag 'vx.y.z+build'
   ```

   Confirm anonymous downloads and hashes on every available source, then test update discovery, download/resume, verification, and installation from an older installed version. If an asset is wrong, withdraw it or publish a new version; do not overwrite it with different bytes.

## Standard Shorebird Patch flow

1. Confirm the change is Dart-only and identify the exact released baseline `x.y.z+build`. Use the baseline's own acceptance version; do not use `-BuildName` or `-BuildNumber`.
2. Optionally compile without uploading:

   ```powershell
   ./tool/build_release.ps1 -Target apk -Patch -ReleaseVersion 'x.y.z+build' -DryRun
   ./tool/build_release.ps1 -Target windows -Patch -ReleaseVersion 'x.y.z+build' -DryRun
   ```

3. After explicit publication authorization, use clean committed source, a matching Full report, and complete platform acceptance:

   ```powershell
   ./tool/build_release.ps1 -Target apk -Patch -ReleaseVersion 'x.y.z+build' `
     -VerificationReport <full-results.json> `
     -AcceptanceReport <android-baseline-acceptance.json>
   ./tool/build_release.ps1 -Target windows -Patch -ReleaseVersion 'x.y.z+build' `
     -VerificationReport <full-results.json> `
     -AcceptanceReport <windows-baseline-acceptance.json>
   ```

4. Check the actual Shorebird CLI/server result and record the returned patch number, server ID, channel, and real compiled artifact. Do not infer them from local SDK metadata.

   ```powershell
   python tool/release_provenance.py patch-receipt --root . `
     --manifest <patch-provenance.json> `
     --artifact <actual-patch-artifact> `
     --patch-number <number> --server-id <id> --channel <staging-or-stable>
   ```

   Until this succeeds, the record remains `awaiting-patch-receipt`; do not claim the remote patch was verified.
5. Install the matching baseline on a dedicated test device, confirm the expected patch downloads, and fully restart the application to verify activation and the fixed behavior. Do not force-close a user's application to apply an update. If a patch-specific announcement is needed, use a GitHub prerelease tagged `vx.y.z+build-patch.N`, where `N` is the real patch number; the full-version announcement remains a separate normal Release.
