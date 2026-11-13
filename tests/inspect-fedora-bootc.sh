#!/usr/bin/env bash
set -euo pipefail

echo "=== Search VA-API, OVMF, OSK, audio, wifi, file manager packages ==="
dnf5 search vaapi i965 ovmf edk2 keyboard greeter pcmanfm thunar nautiluspipewire 2>&1 | head -n 80 || true
echo "=== Specific repoquery ==="
dnf5 repoquery --qf '%{name} %{version}-%{release} (%{arch})\n' \
  '*vaapi*' '*i965*' '*edk2*' '*ovmf*' '*kbd*' '*greeter*' \
  'pcmanfm*' 'thunar*' 'pipewire*' 'wireplumber*' \
  'NetworkManager*' 'bluez*' 'blueman*' 'brightnessctl' 'playerctl' \
  'grim' 'slurp' 'wl-clipboard' 'polkit*' 'wtype' 'ydotool' 2>&1 || true
