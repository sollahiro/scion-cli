# AGENTS.md

Guidance for AI agents working on this repository.

## What this repository is

A fork of [reown-com/reown-swift](https://github.com/reown-com/reown-swift) patched for **macOS CLI compatibility**. It is vendored inside `scion-cli/` and managed as part of the scion monorepo (not a git submodule).

Used by: `scion-cli` only. `scion-ios` references the upstream directly.

## Build

```bash
swift build --product scion
```

Run from `scion-cli/` (the parent package), not from this directory.

## Patches — do not revert

The following changes were made to the upstream source. Do not revert them.

### `Sources/WalletConnectKMS/Keychain/KeychainStorage.swift`
`accessGroup` is `String?` (upstream: `String`). When `nil`, `kSecAttrAccessGroup` is omitted from Keychain queries. **Reason:** macOS CLI apps have no App Group entitlement; passing the key causes `errSecMissingEntitlement` at runtime.

### `Sources/WalletConnectSign/Auth/Link/LinkEnvelopesDispatcher.swift`
`UIApplication.shared.open()` calls are wrapped in `#if os(iOS)`. On macOS, the dispatcher throws `Errors.failedToOpenUniversalLink` instead. **Reason:** `UIApplication` does not exist on macOS; Link Mode is not used in the CLI.

### Factory files (`NetworkingClientFactory`, `RelayClientFactory`, `PairingClientFactory`, `SignClientFactory`)
Each passes `accessGroup: nil` on macOS via `#if os(macOS)`. **Reason:** required by the `KeychainStorage` patch above.

## Keeping this file up to date

When modifying any file in this directory, update this `AGENTS.md` accordingly:
- New patch → add an entry under "Patches — do not revert"
- Reverted patch → remove the entry
- Structural change → update the relevant section

## Syncing with upstream

This fork is pinned. If you need to pull in upstream changes:
1. Download the changed files from upstream manually
2. Re-apply the patches above
3. Verify `swift build --product scion` passes
