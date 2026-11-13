#!/usr/bin/env bash
set -euo pipefail

# Launch minimal labwc session running the adaptive Quickshell Greetd Greeter
GREETER_DIR="${XDG_RUNTIME_DIR:-/tmp}/transformer-greeter-labwc"
mkdir -p "$GREETER_DIR"

cat << 'EOF' > "$GREETER_DIR/rc.xml"
<?xml version="1.0"?>
<labwc_config>
  <core><decoration>server</decoration></core>
  <touch deviceName="SIS0817:00 0457:1071" mapToOutput="DSI-1" mouseEmulation="no" />
  <windowRules>
    <windowRule identifier="*" serverDecoration="no">
      <action name="Maximize" />
    </windowRule>
  </windowRules>
  <libinput>
    <device category="touchpad">
      <naturalScroll>yes</naturalScroll>
      <tap>yes</tap>
      <scrollFactor>0.45</scrollFactor>
    </device>
  </libinput>
</labwc_config>
EOF

# Use Qt software scenegraph backend for fast boot-to-greeter & zero Mesa shader overhead
export QT_QPA_PLATFORM=wayland
export QT_QUICK_BACKEND=software
exec labwc -C "$GREETER_DIR" -s "/usr/bin/quickshell -p /etc/xdg/quickshell/transformeros/greeter.qml"
