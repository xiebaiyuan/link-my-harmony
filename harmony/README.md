# 鸿笺 / Folio — HarmonyOS client

This directory contains the native HarmonyOS (ArkTS + ArkUI, Stage model) client for Linkwarden.

See the [root README](../README.md) for project goals, upstream attribution (**[Linkwarden](https://github.com/linkwarden/linkwarden)**), signing setup, and full getting‑started instructions. This file only lists directory‑local reminders for contributors.

## Quick commands

```bash
# run the pure-JS helper tests
node --test tooling/session-state.test.mjs

# full package build (path to hvigorw depends on your CLI install)
/opt/command-line-tools/bin/hvigorw assembleApp
```

Build artifacts:

- `build/outputs/default/harmony-default-unsigned.app`
- `entry/build/default/outputs/default/app/entry-default.hap`
- `entry/build/default/outputs/default/entry-default-unsigned.hap`

Install a signed HAP on a connected device:

```bash
# adjust to your local HarmonyOS SDK location
"$HOME/Library/OpenHarmony/Sdk/12/toolchains/hdc" list targets
"$HOME/Library/OpenHarmony/Sdk/12/toolchains/hdc" install -r \
  entry/build/default/outputs/default/app/entry-default.hap
```

## Signing (don't commit secrets)

`build-profile.json5` is **git‑ignored** — it contains absolute paths and encrypted passwords unique to your machine. New clones must:

```bash
cp build-profile.template.json5 build-profile.json5
# edit build-profile.json5 with your signing material (DevEco can auto-fill)
```

## Notes

- Tokens are persisted to local preferences via `services/SessionStorage.ets`. If you rotate the server URL from Settings, sign‑in is reset automatically.
- The whole UI currently lives in `entry/src/main/ets/pages/Index.ets` — intentional for the MVP. Split when it gets in the way.
