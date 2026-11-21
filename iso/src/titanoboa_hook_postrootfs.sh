#!/usr/bin/env bash
#
# Installs and configures Anaconda in the live image so it installs the
# BlueBuild payload (IMAGE_REF:IMAGE_TAG) from the live system's container storage.
# Called from build.sh, which exports IMAGE_REF, IMAGE_TAG, DESKTOP and NVIDIA.
set -exo pipefail

: "${IMAGE_REF:?}" "${IMAGE_TAG:?}"
NVIDIA="${NVIDIA:-false}"

# Remove all versionlocks, in order to avoid dependency issues
dnf -qy versionlock clear || :

# Anaconda (its Web UI runs in Firefox, which is installed here if the image doesn't ship it)
OPENH264=()
if dnf repolist --all 2>/dev/null | grep -q '^fedora-cisco-openh264'; then
    OPENH264=(--enable-repo=fedora-cisco-openh264)
fi
dnf install -qy "${OPENH264[@]}" --allowerasing \
    firefox anaconda-live libblockdev-btrfs libblockdev-lvm libblockdev-dm

mkdir -p /var/lib/rpm-state # Needed for Anaconda Web UI

# Used to show the installation log if the installer fails
dnf install -qy --setopt=install_weak_deps=0 yad

# BlueBuild Anaconda profile (matches ID=fedora in os-release).
# The password spoke/page is hidden so the installer does not ask for a root password.
mkdir -p /etc/anaconda/profile.d /etc/anaconda/conf.d
cat >/etc/anaconda/profile.d/bluebuild.conf <<'PROFILE'
# Anaconda configuration file for BlueBuild base images

[Profile]
profile_id = bluebuild

[Profile Detection]
os_id = fedora

[Network]
default_on_boot = FIRST_WIRED_WITH_LINK

[Bootloader]
efi_dir = fedora
menu_auto_hide = True

[Storage]
default_scheme = BTRFS
btrfs_compression = zstd:1
default_partitioning =
    /     (min 1 GiB, max 70 GiB)
    /home (min 500 MiB, free 50 GiB)
    /var  (btrfs)

[User Interface]
hidden_spokes =
    PasswordSpoke

hidden_webui_pages =
    root-password

[Localization]
use_geolocation = False
PROFILE

# Set Anaconda Payload to use flathub
cat >>/etc/anaconda/conf.d/anaconda.conf <<'CONF'
[Payload]
flatpak_remote = flathub https://dl.flathub.org/repo/
CONF

# Default kickstart: install the payload from containers-storage
cat >>/usr/share/anaconda/interactive-defaults.ks <<KICKSTART

# Remove the efi dir, must match efi_dir from the profile config
%pre-install --erroronfail
rm -rf /mnt/sysroot/boot/efi/EFI/fedora
%end

# Open a dialog with the installation logs
%onerror
run0 --user=liveuser yad \\
    --timeout=0 \\
    --text-info \\
    --no-buttons \\
    --width=600 \\
    --height=400 \\
    --text="An error occurred during installation. Please report this issue to the developers." \\
    < /tmp/anaconda.log
%end

ostreecontainer --url=${IMAGE_REF}:${IMAGE_TAG} --transport=containers-storage --no-signature-verification
%include /usr/share/anaconda/post-scripts/install-configure-upgrade.ks
%include /usr/share/anaconda/post-scripts/disable-fedora-flatpak.ks
%include /usr/share/anaconda/post-scripts/install-flatpaks.ks
%include /usr/share/anaconda/post-scripts/restore-selinux-labels.ks

KICKSTART

# Make the installed system follow the signed image in the registry for updates
cat >>/usr/share/anaconda/post-scripts/install-configure-upgrade.ks <<KICKSTART
%post --erroronfail --log=/tmp/anacoda_custom_logs/bootc-switch.log
bootc switch --mutate-in-place --enforce-container-sigpolicy --transport registry ${IMAGE_REF}:${IMAGE_TAG}
%end
KICKSTART

# Copy the flatpaks installed in the live image to the new system
cat >>/usr/share/anaconda/post-scripts/install-flatpaks.ks <<'KICKSTART'
%post --erroronfail --nochroot --log=/tmp/anacoda_custom_logs/install-flatpaks.log
deployment="$(ostree rev-parse --repo=/mnt/sysimage/ostree/repo ostree/0/1/0)"
target="/mnt/sysimage/ostree/deploy/default/deploy/$deployment.0/var/lib/"
mkdir -p "$target"
rsync -aAXUHKP --open-noatime /var/lib/flatpak "$target"
sync "$target"
%end
KICKSTART

# Disable Fedora Flatpak Repo
cat >>/usr/share/anaconda/post-scripts/disable-fedora-flatpak.ks <<'KICKSTART'
%post --erroronfail --log=/tmp/anacoda_custom_logs/disable-fedora-flatpak.log
systemctl disable flatpak-add-fedora-repos.service || :
%end
KICKSTART

# Restore SELinux labels (the flatpak copy above does not keep them)
cat >>/usr/share/anaconda/post-scripts/restore-selinux-labels.ks <<'KICKSTART'
%post --erroronfail --log=/tmp/anacoda_custom_logs/restore-selinux-labels.log
# Make sure SELinux is disabled so restorecon can work.
setenforce 0 || true

# Fix critical policy-store labels.
restorecon -R /etc/selinux

# Properly restore SELinux labels for Flatpak.
restorecon -R /var/lib/flatpak
%end
KICKSTART

# Create the log directory the %post scripts above write to
cat >>/usr/share/anaconda/interactive-defaults.ks <<'KICKSTART'
%pre
mkdir -p /tmp/anacoda_custom_logs
%end
KICKSTART

### Secure Boot key enrollment (NVIDIA images only) ###
# The NVIDIA images ship kernel modules signed with the BlueBuild akmods key,
# so Secure Boot users must enroll it (same flow as `ujust enroll-secure-boot-key`).
if [ "$NVIDIA" = "true" ]; then
    SECUREBOOT_KEY="/etc/pki/akmods/certs/akmods-blue-build.der"

    command -v mokutil >/dev/null || dnf install -qy mokutil

    cat >>/usr/share/anaconda/post-scripts/secureboot-enroll-key.ks <<EOF
%post --erroronfail --nochroot --log=/tmp/anacoda_custom_logs/secureboot-enroll-key.log
set -oue pipefail

readonly ENROLLMENT_PASSWORD="bluebuild"
readonly SECUREBOOT_KEY="/mnt/sysimage$SECUREBOOT_KEY"

if [[ ! -d "/sys/firmware/efi" ]]; then
	echo "EFI mode not detected. Skipping key enrollment."
	exit 0
fi

if [[ ! -f "\$SECUREBOOT_KEY" ]]; then
	echo "Secure boot key not found in the installed system. Skipping."
	exit 0
fi

mokutil --timeout -1 || :
echo -e "\$ENROLLMENT_PASSWORD\n\$ENROLLMENT_PASSWORD" | mokutil --import "\$SECUREBOOT_KEY" || :
%end
EOF

    cat >>/usr/share/anaconda/interactive-defaults.ks <<'KICKSTART'
%include /usr/share/anaconda/post-scripts/secureboot-enroll-key.ks
KICKSTART
fi

### Live session runtime tweaks ###

# Disable services that should not run in a live session
(
    set +e
    for s in \
        rpm-ostree-countme.service \
        bootloader-update.service \
        rpm-ostreed-automatic.timer \
        bootc-fetch-apply-updates.timer \
        flatpak-system-updates.timer; do
        systemctl disable "$s" 2>/dev/null || true
    done

    for s in flatpak-user-updates.timer; do
        systemctl --global disable "$s" 2>/dev/null || true
    done
)

# Tools for troubleshooting from the live session
dnf -yq install gparted || :

if [ "$NVIDIA" = "true" ]; then
    # GTK apps do not open with the proprietary driver on the live ISO
    mkdir -p /etc/environment.d /etc/skel/.config/environment.d
    echo "GSK_RENDERER=gl" >>/etc/environment.d/99-nvidia-fix.conf
    echo "GSK_RENDERER=gl" >>/etc/skel/.config/environment.d/99-nvidia-fix.conf

    # Reenable nouveau
    for pkg in nvidia-gpu-firmware mesa-vulkan-drivers; do
        dnf -yq reinstall --allowerasing $pkg ||
            dnf -yq install --allowerasing $pkg || :
    done
fi