# syntax=docker/dockerfile:1
# =============================================================================
# Stage 1: Compile transformerd (Rust) & wvkbd-mobintl (C/Wayland OSK)
# =============================================================================
FROM quay.io/fedora/fedora-bootc:45 AS builder

RUN dnf5 install -y --setopt=install_weak_deps=False \
        rust \
        cargo \
        gcc \
        make \
        git \
        pkgconf-pkg-config \
        wayland-devel \
        wayland-protocols-devel \
        cairo-devel \
        pango-devel \
        libxkbcommon-devel && \
    mkdir -p /out

COPY transformerd /src/transformerd
RUN rustc -O --edition=2021 -C strip=symbols \
        /src/transformerd/src/main.rs \
        -o /out/transformerd && \
    ln -sf transformerd /out/transformerdctl

RUN git clone --depth 1 https://github.com/jjsullivan5196/wvkbd.git /src/wvkbd && \
    make -C /src/wvkbd wvkbd-mobintl -j"$(nproc)" && \
    install -m 0755 /src/wvkbd/wvkbd-mobintl /out/wvkbd-mobintl && \
    strip /out/wvkbd-mobintl

# =============================================================================
# Stage 2: TransformerOS Fedora 45 Atomic (bootc) Image for ASUS T100TAS
# =============================================================================
FROM quay.io/fedora/fedora-bootc:45

LABEL org.opencontainers.image.title="TransformerOS" \
      org.opencontainers.image.description="Fedora 45 Atomic (bootc) OS for ASUS Transformer Book T100TAS (32-bit IA32 UEFI + 2-in-1 Laptop/Tablet Wayland Shell)" \
      org.opencontainers.image.source="https://github.com/Piernik-cpu/TransformerOS" \
      containers.bootc="1"

# 1. Enable RPM Fusion Free (for Intel Bay Trail i965 VA-API driver) and install packages
RUN dnf5 install -y --setopt=install_weak_deps=False \
        "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-45.noarch.rpm" || true && \
    dnf5 install -y --setopt=install_weak_deps=False \
        shim-ia32 \
        grub2-efi-ia32 \
        grub2-efi-ia32-cdboot \
        grub2-efi-ia32-modules \
        efibootmgr \
        alsa-sof-firmware \
        alsa-ucm \
        alsa-utils \
        brcmfmac-firmware \
        intel-audio-firmware \
        intel-gpu-firmware \
        iio-sensor-proxy \
        pipewire \
        pipewire-pulseaudio \
        pipewire-alsa \
        pipewire-utils \
        wireplumber \
        upower \
        power-profiles-daemon \
        gamemode \
        libva-utils \
        NetworkManager \
        NetworkManager-wifi \
        NetworkManager-bluetooth \
        network-manager-applet \
        wireless-regdb \
        iw \
        bluez \
        bluez-obexd \
        blueman \
        rfkill \
        greetd \
        tuigreet \
        labwc \
        waybar \
        fuzzel \
        foot \
        mako \
        swaybg \
        swayidle \
        gtklock \
        wlopm \
        wlr-randr \
        kanshi \
        xdg-desktop-portal \
        xdg-desktop-portal-wlr \
        xdg-desktop-portal-gtk \
        wl-clipboard \
        grim \
        slurp \
        wtype \
        brightnessctl \
        playerctl \
        libnotify \
        quickshell \
        gtk4 \
        gtk4-layer-shell \
        libadwaita \
        python3 \
        python3-gobject \
        polkit \
        pcmanfm \
        gvfs \
        udisks2 \
        btrfs-progs \
        snapper \
        earlyoom \
        zram-generator \
        openssh-server \
        sudo \
        passwd \
        shadow-utils \
        firefox \
        flatpak \
        fontconfig \
        google-noto-sans-fonts && \
    (dnf5 install -y --setopt=install_weak_deps=False intel-vaapi-driver || \
     dnf5 install -y --setopt=install_weak_deps=False libva-intel-driver || true) && \
    dnf5 clean all && \
    rm -rf /var/cache/dnf /var/lib/dnf/repos

# 2. Install compiled transformerd + wvkbd-mobintl binaries
COPY --from=builder /out/transformerd /usr/bin/transformerd
COPY --from=builder /out/transformerdctl /usr/bin/transformerdctl
COPY --from=builder /out/wvkbd-mobintl /usr/bin/wvkbd-mobintl

# 3. Install ASUS T100TAS Broadcom Bluetooth patch & Wi-Fi NVRAM firmware
COPY firmware/brcm/ /usr/lib/firmware/brcm/
COPY bootia32.efi /usr/share/transformeros/boot/bootia32.efi

# 4. Install system configurations (dracut, kargs.d, zram, sysctl, tmpfiles, udev, systemd, greetd, polkit)
COPY system/ /

# 5. Install TransformerOS Shell, Adaptive Greeter, Lock Screen, Labwc & Waybar configs
COPY shell/transformer-greeter.py /usr/bin/transformer-greeter
COPY shell/transformer-greeter-session.sh /usr/bin/transformer-greeter-session
COPY shell/transformer-shell.py /usr/bin/transformer-shell
COPY shell/transformer-session.sh /usr/bin/transformer-session
COPY shell/labwc/ /etc/skel/.config/labwc/
COPY shell/waybar/ /etc/skel/.config/waybar/
COPY shell/quickshell/ /etc/xdg/quickshell/transformeros/
COPY shell/firefox/t100tas-prefs.js /usr/lib64/firefox/defaults/pref/t100tas-prefs.js

RUN chmod 0755 \
        /usr/bin/transformerd \
        /usr/bin/wvkbd-mobintl \
        /usr/bin/transformer-greeter \
        /usr/bin/transformer-greeter-session \
        /usr/bin/transformer-shell \
        /usr/bin/transformer-session \
        /etc/skel/.config/labwc/autostart && \
    cp -a /etc/skel/.config/labwc/rc-docked.xml /etc/skel/.config/labwc/rc.xml && \
    # Ensure greeter user has video/input group access for Wayland DRM + touch + backlight
    (getent passwd greeter >/dev/null || useradd -r -M -d /var/lib/greetd -s /sbin/nologin greeter) && \
    usermod -aG video,input greeter || true && \
    # Enable core services
    systemctl enable \
        greetd.service \
        earlyoom.service \
        power-profiles-daemon.service \
        iio-sensor-proxy.service \
        NetworkManager.service \
        bluetooth.service \
        sshd.service \
        fstrim.timer \
        transformeros-auto-update.timer && \
    systemctl disable \
        NetworkManager-wait-online.service \
        systemd-oomd.service 2>/dev/null || true

# 6. Refresh bootupd metadata so 32-bit IA32 EFI (BOOTIA32.EFI / shimia32.efi / grubia32.efi) is tracked,
#    and rebuild initramfs with MMC/SDHCI & Bay Trail PMIC/GPIO/PWM preloaded
RUN set -euo pipefail; \
    if [ -d /usr/lib/bootupd/updates ]; then \
        rm -rf /usr/lib/bootupd/updates && \
        bootupctl backend generate-update-metadata / || true; \
    fi; \
    KVER="$(cd /usr/lib/modules && ls -1 | head -n 1)"; \
    dracut --force --no-hostonly --zstd --kver "$KVER" "/usr/lib/modules/$KVER/initramfs.img"; \
    rm -rf /boot/grub2 /run/dnf /run/selinux-policy /tmp/* /var/tmp/* /var/log/dnf5* /var/cache/* 2>/dev/null || true
