# 鸿笺 / Folio

An **unofficial, third‑party HarmonyOS Next client for [Linkwarden](https://github.com/linkwarden/linkwarden)**. Written in ArkTS + ArkUI (Stage model), it talks to any Linkwarden server (cloud or self‑hosted) through the public REST API.

> **Not affiliated with Linkwarden.** This project is an independent client. All server‑side logic, API design, and the name "Linkwarden" belong to the upstream project — please send server‑side issues there, not here.

<p>
  <img alt="Platform" src="https://img.shields.io/badge/platform-HarmonyOS%20Next-1F6FEB">
  <img alt="Language" src="https://img.shields.io/badge/lang-ArkTS-3178C6">
  <img alt="Upstream" src="https://img.shields.io/badge/upstream-Linkwarden-0F172A">
  <img alt="Status" src="https://img.shields.io/badge/status-early%20MVP-orange">
</p>

## Credits & upstream

Everything that makes this app useful comes from the Linkwarden team — **please star and support them first**:

- **Linkwarden (the real thing)**: <https://github.com/linkwarden/linkwarden>
- Official website: <https://linkwarden.app>
- Official cloud: <https://cloud.linkwarden.app>
- Official mobile app (React Native, reference implementation for this port): [`linkwarden/apps/mobile`](https://github.com/linkwarden/linkwarden/tree/main/apps/mobile)

The count/aggregation behavior, dashboard v2 endpoint usage, and tag pagination handling in this client are modeled after the official mobile app so feature parity stays close.

A spiritual thank‑you also to [`JGeek00/MyLinks`](https://github.com/JGeek00/my-links) — the iOS client that made me want a HarmonyOS one.

## Features (current MVP)

- Sign in against any Linkwarden instance (`/api/v1/session`)
- Dashboard with server‑accurate counts (Links / Collections / Pinned / Tags) via `/api/v2/dashboard`
- Links list with cursor pagination, search, collection filter, pinned filter
- Create / edit / delete links, with collection + tag pickers
- Pin / unpin
- Create collection (name, description, color, parent)
- Share Intent — accept a URL from the system share sheet and pre‑fill the Add dialog
- Theme picker (light / dark / system)
- i18n: 简体中文 / English

Not yet covered: RSS, archival downloads, bulk actions, import/export.

## Requirements

- **DevEco Studio** ≥ 5.0 (2024 release or newer)
- **HarmonyOS SDK** `6.0.0(20)` — both `compatibleSdkVersion` and `targetSdkVersion` in `harmony/build-profile.json5`
- A real HarmonyOS Next device or a DevEco emulator
- A Linkwarden server to point at (cloud or self‑hosted)

## Getting started

### 1. Clone

```bash
git clone https://github.com/<you>/link-my-harmony.git
cd link-my-harmony
```

### 2. Create your local signing profile

The repository **does not** contain any signing material — every developer must generate their own HarmonyOS certificate.

Recommended (GUI):

1. Open `harmony/` in DevEco Studio.
2. `File → Project Structure → Signing Configs → Automatically generate signing`.
3. DevEco writes a `.cer`, `.p12`, and `.p7b` under `~/.ohos/config/` and injects the full `material` block into `build-profile.json5`.

Manual (CLI users / CI / AppGallery Connect release cert):

```bash
cp harmony/build-profile.template.json5 harmony/build-profile.json5
# then edit harmony/build-profile.json5 and fill in:
#   certpath      absolute path to your .cer
#   profile       absolute path to your .p7b
#   storeFile     absolute path to your .p12
#   storePassword DevEco-encrypted string (or plain text for local dev)
#   keyAlias      alias chosen when the cert was created
#   keyPassword   DevEco-encrypted string
```

`harmony/build-profile.json5` is git‑ignored — your signing material will never be committed even if you edit it. Only `harmony/build-profile.template.json5` lives in version control.

### 3. Build & run

GUI:

- Pick your device/emulator in DevEco, press **Run** on the `entry` module.

CLI:

```bash
cd harmony
# Path to hvigorw depends on how you installed the HarmonyOS CLI tools.
# Typical install location:
/opt/command-line-tools/bin/hvigorw assembleApp
```

Artifacts are written to:

```
harmony/build/outputs/default/harmony-default-unsigned.app
harmony/entry/build/default/outputs/default/app/entry-default.hap
harmony/entry/build/default/outputs/default/entry-default-unsigned.hap
```

Install a signed HAP onto a connected device:

```bash
# adjust to your HarmonyOS SDK location
"$HOME/Library/OpenHarmony/Sdk/12/toolchains/hdc" list targets
"$HOME/Library/OpenHarmony/Sdk/12/toolchains/hdc" install -r \
  harmony/entry/build/default/outputs/default/app/entry-default.hap
```

### 4. Point the app at your Linkwarden server

The app ships with `https://cloud.linkwarden.app` as the default instance URL. On first launch:

1. Enter your username + password on the login screen.
2. If you self‑host, open **Menu → Server** and paste your instance URL, then tap **Apply Server** — the session resets and you can sign in again.

No personal server URL is baked into the source — every developer/user chooses their own.

### 5. (Optional) Run the helper tests

The pure‑JS utilities under `harmony/tooling/` have a small test suite:

```bash
cd harmony
node --test tooling/session-state.test.mjs
```

## Project layout

```
harmony/
├── AppScope/app.json5                  app metadata (bundleName, version)
├── build-profile.template.json5        committed template — copy to build-profile.json5
├── build-profile.json5                 LOCAL ONLY, git-ignored, contains your signing paths
├── entry/src/main/
│   ├── ets/
│   │   ├── common/                     Models, Query, SessionState, ShareIntent, UI design tokens
│   │   ├── services/                   LinkwardenApi + SessionStorage
│   │   ├── pages/Index.ets             the whole UI (MVP, intentionally one page)
│   │   ├── entryability/               Stage-model entry ability
│   │   └── shareability/               share-sheet extension
│   └── resources/                      i18n strings, images
└── tooling/                            tiny Node helpers with tests (shared query/session logic)
```

## Changing the bundle ID

If you want to publish your own build to AppGallery, replace `bundleName` in `harmony/AppScope/app.json5` with something you own (e.g. `com.yourname.linkmyharmony`). AppGallery Connect will reject a non‑owned bundle ID.

## Contributing

Bug reports and PRs are welcome — but please:

- File **Linkwarden server or API** issues on the [upstream repo](https://github.com/linkwarden/linkwarden/issues), not here.
- This repo only handles the HarmonyOS client UI, ArkTS code, and packaging.

## License

Not yet chosen. Until a `LICENSE` file is added, this repository is offered **source‑available for personal evaluation**; no rights are granted beyond viewing and building locally. A permissive license (MIT / Apache‑2.0) or AGPL‑3.0 (to match upstream) will be added before any wider distribution.

## Acknowledgements

- **Linkwarden team** — for building the only self‑hosted bookmark manager I actually use.
- **JGeek00** — for `MyLinks`, the iOS client that inspired this one.
- HarmonyOS ArkUI / ArkTS team — for the Stage model and the 6.x toolchain.
