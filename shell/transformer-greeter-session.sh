#!/usr/bin/env bash
set -euo pipefail

# Launch minimal labwc session running the adaptive dock-aware TransformerOS Greeter
GREETER_DIR="${XDG_RUNTIME_DIR:-/tmp}/transformer-greeter-labwc"
mkdir -p "$GREETER_DIR"

cat << 'EOF' > "$GREETER_DIR/rc.xml"
<?xml version="1.0"?>
<labwc_config>
  <core><decoration>none</decoration></core>
  <touch deviceName="SIS0817:00 0457:1071" mapToOutput="DSI-1" mouseEmulation="no" />
  <libinput>
    <device category="touchpad">
      <naturalScroll>yes</naturalScroll>
      <tap>yes</tap>
    </device>
  </libinput>
</labwc_config>
EOF

exec labwc -C "$GREETER_DIR" -s "/usr/bin/transformer-greeter"
