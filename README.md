# BlueBuild Base Images: Live ISOs <a href="https://github.com/ShadowElixir/base-images/actions/workflows/build-iso.yml"><img src="https://github.com/ShadowElixir/base-images/actions/workflows/build-iso.yml/badge.svg" alt="iso build badge" height="28"/></a>

Live + installer ISOs for the [BlueBuild base images](https://github.com/blue-build/base-images), plus a small download site.

## Images covered

| Image / Desktop | Target image |
|-----------------|--------------|
| COSMIC | `fedora-cosmic` |
| GNOME | `fedora-silverblue` |
| KDE Plasma | `fedora-kinoite` |
| Fedora Base | `fedora-base` |

Fedora Base is a minimal, desktop-free image. Its ISO uses a small IceWM + LightDM graphical live session so the installer can run; **IceWM is only part of the live ISO and is not installed into the Fedora Base system**. Fedora Base supports the same three GPU variants as the desktop images: standard AMD/Intel (`fedora-base`), NVIDIA open kernel modules (`fedora-base-nvidia-open`), and NVIDIA 580 (`fedora-base-nvidia`). Both `latest` and `gts` tags are available for all three variants.

Each image is built for the `latest` and `gts` tags. With the current matrix this produces 48 ISO jobs: 36 desktop-image jobs and 12 Fedora Base jobs (three GPU variants, two release tracks, and two architectures).

## How it works

`.github/workflows/build-iso.yml` pulls `ghcr.io/blue-build/base-images/<image>:<tag>`, layers the live/installer tooling on top (`iso/`), and packs it with [Titanoboa](https://github.com/ublue-os/titanoboa). Fedora Base uses the same target image for installation, with a separate minimal IceWM live session to provide the graphical installer environment. The desktop images use their corresponding desktop environment for the live session. The pipeline otherwise follows ShadowOS, minus the Bazzite kernel swap and flatpak lists (BlueBuild images already use the stock signed Fedora kernel and ship no flatpaks).

- Runs daily and on manual dispatch. Use the `only` input to build a subset (e.g. `kinoite-nvidia-open` or `base`).
- ISOs are uploaded as job artifacts (4 day retention), which the site links to through nightly.link.
- NVIDIA ISOs, including Fedora Base, queue the BlueBuild signing key for Secure Boot enrollment (password `bluebuild`). Fedora Base uses IceWM only in the live installer; its installed system remains desktop-free.