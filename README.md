# BlueBuild Base Images: Live ISOs

Live + installer ISOs for the [BlueBuild base images](https://github.com/blue-build/base-images), plus a small download site.

## Images covered

| Desktop | Image | GPU variants | Arch |
|---------|-------|--------------|------|
| COSMIC  | `fedora-cosmic`     | AMD/Intel, `-nvidia-open`, `-nvidia` (580) | x86_64, arm64 |
| GNOME   | `fedora-silverblue` | same | same |
| KDE     | `fedora-kinoite`    | same | same |

Each is built for the `latest` and `gts` tags: 36 ISO jobs in total.

`fedora-base` is **skipped on purpose**: it ships no desktop, so a live session has nothing to boot into.

## How it works

`.github/workflows/build-iso.yml` pulls `ghcr.io/blue-build/base-images/<image>:<tag>`, layers the live/installer tooling on top (`iso/`), and packs it with [Titanoboa](https://github.com/ublue-os/titanoboa). Same pipeline as ShadowOS, minus the Bazzite kernel swap and flatpak lists (BlueBuild images already use the stock signed Fedora kernel and ship no flatpaks).

- Runs daily and on manual dispatch. Use the `only` input to build a subset (e.g. `kinoite-nvidia`).
- ISOs are uploaded as job artifacts (4 day retention), which the site links to through nightly.link.
- NVIDIA ISOs queue the BlueBuild signing key for Secure Boot enrollment (password `bluebuild`).