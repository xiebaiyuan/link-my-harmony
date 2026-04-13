# Linkwarden HarmonyOS Native MVP

This directory contains a native HarmonyOS (ArkTS + ArkUI, Stage model) MVP client for Linkwarden.

## Implemented Scope

- Login via `/api/v1/session`
- Links listing via `/api/v1/search`
- Add link via `/api/v1/links`
- Sign out and in-memory session reset
- Basic search and cursor pagination

## Local Development (DevEco Studio)

1. Open `apps/harmony` as a HarmonyOS project in DevEco Studio.
2. Ensure HarmonyOS SDK and command-line tools are installed.
3. Build and run the `entry` module on an emulator/device.

## Command-Line Build

Build the app package:

```bash
/opt/command-line-tools/bin/hvigorw assembleApp
```

Unsigned outputs are written to:

- `build/outputs/default/harmony-default-unsigned.app`
- `entry/build/default/outputs/default/app/entry-default.hap`
- `entry/build/default/outputs/default/entry-default-unsigned.hap`

## Signing

The current repository ships with a signing template only. To produce an installable signed package:

1. Generate or download a HarmonyOS debug/release certificate set in DevEco Studio or AppGallery Connect.
2. Edit `build-profile.json5` and replace the commented `signingConfigs` example with real file paths and passwords.
3. Re-run `/opt/command-line-tools/bin/hvigorw assembleApp`.

After a real signing profile is configured, install the signed HAP:

```bash
/Users/xiebaiyuan/Library/OpenHarmony/Sdk/12/toolchains/hdc list targets
/Users/xiebaiyuan/Library/OpenHarmony/Sdk/12/toolchains/hdc install -r /Users/xiebaiyuan/workspace/linkwarden/apps/harmony/entry/build/default/outputs/default/app/entry-default.hap
```

If you prefer the GUI path, open the project in DevEco Studio, choose a connected device/emulator, and run the `entry` module directly. DevEco can help manage the signing assets.

## Notes

- Current MVP stores token in memory only.
- Follow-up iteration should migrate auth persistence to encrypted preferences.
