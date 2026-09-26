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
