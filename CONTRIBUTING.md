# Contributing to 鸿笺 / Folio

Thanks for your interest in making this client better. A few quick rules before you open an issue or PR.

## Is this the right repo?

This repository only owns the **HarmonyOS client** (ArkTS / ArkUI code, packaging, signing docs, HarmonyOS‑specific bugs).

Please file issues elsewhere for:

| Topic | Where |
|-------|-------|
| Linkwarden server bugs, API behavior, missing server features | <https://github.com/linkwarden/linkwarden/issues> |
| Linkwarden web / browser extension / other official clients | <https://github.com/linkwarden/linkwarden/issues> |
| Linkwarden account or billing on cloud.linkwarden.app | <https://linkwarden.app> / support@linkwarden.app |
| This HarmonyOS client's UI, crashes, ArkTS code | **right here** |

If you're unsure, open a GitHub Discussion or a short issue here and we can redirect.

## Before you file an issue

Please include:

- HarmonyOS version (system → About Phone)
- DevEco Studio version (if you built from source)
- Linkwarden server version (Settings → About in the web UI)
- Whether the server is `cloud.linkwarden.app` or self‑hosted (no need to share the hostname)
- Steps to reproduce, expected vs. actual behavior, and a log snippet if you have one

Screenshots or screen recordings help a lot — ArkUI bugs are often pixel‑specific.

**Do not paste** your session token, server URL with subdomain secrets, or any link content you would not share publicly.

## Sending a pull request

1. Fork, branch off `master`, name the branch something descriptive (`fix/dashboard-counts`, `feat/rss-list`, …).
2. Keep the change **minimal and surgical** — no drive‑by refactors of unrelated code (see [`CLAUDE.md`](./CLAUDE.md) for the rationale).
3. If you touch `harmony/tooling/*.mjs`, run the tests:
   ```bash
   cd harmony
   node --test tooling/*.test.mjs
   ```
4. For UI changes, include before / after screenshots in the PR description.
5. Don't commit `harmony/build-profile.json5`, `*.p12`, `*.p7b`, `*.cer`, `.ohos/` material, or any `/Users/...` absolute path — these are git‑ignored and there is no reason they should ever leak into a commit.
6. Write commit messages in the Conventional Commits style (`feat:`, `fix:`, `chore:`, `docs:`). Keep the first line ≤ 72 characters.

## Code style

- ArkTS: match the surrounding code. No ESLint rig yet; don't add one in a PR that isn't about linting.
- i18n strings: add the new key to **both** `zh-CN` and `en` resource files.
- Avoid adding new top‑level @State fields to `Index.ets` without discussing — the page is already on the large side.

## Security

Found something exploitable? Please **do not** open a public issue. Email the owner via the email on the GitHub profile, or open a GitHub Security Advisory on this repo.

## Licensing

By contributing you agree that your contribution will be released under the project's [MIT License](./LICENSE).
