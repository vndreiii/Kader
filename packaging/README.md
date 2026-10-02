# Packaging, releases and updates

## Versions

Kader uses semantic versioning, `MAJOR.MINOR.FIX`. The only place the version
lives is `project(Kader VERSION …)` in `CMakeLists.txt`; the PKGBUILD, the
AppImage name and the app (`Qt.application.version`) all read it from there.

## Making a release

1. Bump `project(Kader VERSION x.y.z)` in `CMakeLists.txt`.
2. Add a `## [x.y.z]` section to `CHANGELOG.md` — it becomes the release notes
   shown in the in-app update dialog.
3. Commit, then tag and push: `git tag vx.y.z && git push origin vx.y.z`.

`.github/workflows/release.yml` then builds the Arch package and the AppImage
(the same `build.yml` that CI runs on every push), signs the update manifest
and publishes a GitHub release with:

| asset | used by |
|---|---|
| `Kader-x.y.z-x86_64.AppImage` (+ `.zsync`) | AppImage users / self-update |
| `kader-x.y.z-1-x86_64.pkg.tar.zst` | Arch self-update (`pacman -U`) |
| `kader-update.json` + `.sig` | the in-app updater |
| `SHA256SUMS` | humans |

## How self-update works

`src/UpdateManager.cpp` fetches `kader-update.json` and `kader-update.json.sig`
from `https://github.com/vndreiii/kader/releases/latest/download/`. The
manifest is only trusted if its Ed25519 signature verifies against
`release-signing.pub`; a download is only installed if its SHA-256 matches the
signed manifest.

* **AppImage** — downloaded next to the running AppImage and atomically renamed
  over it; the user is offered a restart.
* **Arch package** (`-DKADER_UPDATE_CHANNEL=arch`, set by the PKGBUILD) — the
  user confirms, the package is fetched and installed with
  `pkexec pacman -U`, then Kader offers a restart.
* **Anything else** (self-built) — the update is announced with a link to the
  release page.

Test against a local mirror of a release with
`KADER_UPDATE_BASE_URL=http://127.0.0.1:8000 kader` (serve a directory holding
the manifest, signature and assets).

## The signing key

CI signs with the repository secret **`KADER_SIGNING_KEY`** (an Ed25519 private
key in PEM form). The matching public key is `release-signing.pub` (raw 32-byte
key, base64). To create or rotate a key:

```sh
openssl genpkey -algorithm ed25519 -out kader-signing.pem
openssl pkey -in kader-signing.pem -pubout -outform DER | tail -c 32 | base64 > packaging/release-signing.pub
# paste kader-signing.pem into Settings → Secrets and variables → Actions → KADER_SIGNING_KEY
```

Keep the private key out of the repository. After rotating, installs built
with the old public key can no longer verify new releases — rotate only when
the key is compromised, and ship the new public key in a release signed with
the old key first.

## Building locally

* Arch: `cd packaging/arch && makepkg -si`.
* AppImage: build with CMake, then
  `packaging/appimage/build-appimage.sh <build-dir> <out-dir>`.
* AI search needs llama.cpp; `packaging/build-llama.sh <prefix>` builds the
  pinned release as static libraries — pass the prefix via
  `-DCMAKE_PREFIX_PATH`. Without it Kader builds with AI search disabled.
