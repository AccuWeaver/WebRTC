# Upstream Sync Procedure

This document describes how to merge new releases from the upstream [`stasel/WebRTC`](https://github.com/stasel/WebRTC) repository into this fork, verify tvOS slices build correctly, and publish a new fork release.

## Prerequisites

- Git CLI with the `upstream` remote configured:
  ```bash
  git remote add upstream https://github.com/stasel/WebRTC.git
  ```
- GitHub CLI (`gh`) installed and authenticated
- Access to trigger GitHub Actions workflows on this fork

## Step 1: Fetch Upstream Tags

```bash
git fetch upstream --tags
```

Identify the new release tag (e.g., `148.0.0`):

```bash
git tag -l | sort -V | tail -5
```

## Step 2: Merge the Upstream Tag

Create a branch for the sync work:

```bash
git checkout -b sync/upstream-148.0.0 main
git merge 148.0.0
```

If the merge completes cleanly, skip to Step 4.

## Step 3: Resolve Merge Conflicts

Conflicts are most likely in the following files due to fork-specific tvOS additions:

### `scripts/build.sh`

- **Preserve**: The `build_tvOS()` function, `TVOS` env var handling, tvOS xcframework assembly logic, and the `validate_tvos.sh` call
- **Accept upstream**: Changes to `build_iOS()`, `build_macOS()`, `build_macCatalyst()`, GN args updates, and any new platform additions
- **Watch for**: Changes to `COMMON_GN_ARGS` or xcframework assembly structure — if upstream modifies how slices are assembled, port the tvOS slice additions to match the new pattern

### `.github/workflows/webrtc-build.yml`

- **Preserve**: The `tvos` input parameter and `TVOS` env var passthrough
- **Accept upstream**: Runner version updates, new build inputs, caching changes

### `.github/workflows/webrtc-release.yml`

- **Preserve**: Any fork-specific environment variables (e.g., `TVOS=true`)
- **Accept upstream**: Schedule changes, release logic updates

### `scripts/release.py`

- **Preserve**: The `TVOS=true` flag in `buildWebRTC()` and any validation gate logic
- **Accept upstream**: API changes, new milestone detection logic, checksum handling

### `Package.swift`

- **Preserve**: `.tvOS(.v15)` in the `platforms` array
- **Accept upstream**: Binary target URL/checksum updates (these will be overwritten on next release anyway)

After resolving conflicts:

```bash
git add .
git commit -m "Merge upstream tag 148.0.0 into fork"
```

## Step 4: Verify tvOS Build Locally (Optional)

If you have the WebRTC build toolchain available locally:

```bash
export TVOS=true
export IOS=true
export MACOS=true
export MAC_CATALYST=true
sh scripts/build.sh
```

Verify the output xcframework contains tvOS slices:

```bash
ls out/WebRTC.xcframework/ | grep tvos
# Expected: tvos-arm64/ and tvos-arm64-simulator/
```

## Step 5: Run CI Pipeline

Push the sync branch and trigger the build workflow:

```bash
git push origin sync/upstream-148.0.0
```

Trigger the manual build workflow via GitHub CLI:

```bash
gh workflow run webrtc-build.yml \
  --ref sync/upstream-148.0.0 \
  -f ios=true \
  -f macos=true \
  -f tvos=true
```

Or trigger via the GitHub Actions UI with the `tvos` input enabled.

## Step 6: Validate CI Output

Wait for the workflow to complete, then verify:

1. **Build succeeded** — all platform builds (iOS, macOS, macOS Catalyst, tvOS) passed
2. **tvOS slices present** — the post-assembly validation step confirmed `tvos-arm64/` and `tvos-arm64-simulator/` directories exist
3. **Validation script passed** — `validate_tvos.sh` compiled successfully against both tvOS device and simulator SDKs
4. **No regressions** — iOS and macOS slices are still present and functional

Check the workflow run:

```bash
gh run list --workflow=webrtc-build.yml --branch=sync/upstream-148.0.0
gh run view <run-id> --log
```

## Step 7: Merge to Main

Once CI passes:

```bash
git checkout main
git merge sync/upstream-148.0.0
git push origin main
```

Or open a PR for team review:

```bash
gh pr create --base main --head sync/upstream-148.0.0 \
  --title "Sync upstream stasel/WebRTC 148.0.0" \
  --body "Merges upstream release 148.0.0. CI verified tvOS slices build successfully."
```

## Step 8: Publish Fork Release

Tag and push the new release:

```bash
git tag 148.0.0
git push origin 148.0.0
```

This triggers the `webrtc-release.yml` workflow which will:
1. Build the full xcframework (iOS + macOS + macOS Catalyst + tvOS)
2. Run `validate_tvos.sh` to confirm tvOS linkability
3. Create a GitHub release draft with the `.xcframework.zip` asset
4. Compute and include the SHA-256 checksum in release notes
5. Open a PR to update `Package.swift` with the new binary URL and checksum

## Troubleshooting

### tvOS build fails after merge

If the tvOS build fails but iOS/macOS succeed, the upstream likely changed GN args or SDK handling:

1. Check if `COMMON_GN_ARGS` changed — new args may conflict with tvOS sysroot patching
2. Check if SDK path resolution changed — `tvosify.sh` sed patterns may need updating
3. Check if `target_environment` handling changed — the `build_tvOS()` function may need arg updates

Fix `scripts/tvosify.sh` or `build_tvOS()` as needed, then re-run CI.

### xcframework assembly fails

If the xcframework assembly step fails:

1. Check if upstream changed the `PlistBuddy` / `lipo` assembly logic
2. Verify tvOS framework binaries exist in the expected output directories
3. Port the tvOS slice additions to match any new assembly pattern

### Validation script fails

If `validate_tvos.sh` fails after a successful build:

1. Check if WebRTC API surface changed (e.g., `RTCPeerConnectionFactory` init signature)
2. Update the validation Swift code in `validate_tvos.sh` to match the new API
3. Check if framework search paths changed in the xcframework directory structure
