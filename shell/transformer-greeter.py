#!/usr/bin/env python3
"""
TransformerOS Greetd IPC Authentication Bridge (`transformer-greeter`)
Used by the Quickshell adaptive login greeter (`/etc/xdg/quickshell/transformeros/greeter.qml`)
to authenticate over the native `$GREETD_SOCK` UNIX socket protocol.
"""

import json
import os
import socket
import struct
import sys


def greetd_roundtrip(sock: socket.socket, payload: dict) -> dict:
    raw = json.dumps(payload).encode("utf-8")
    sock.sendall(struct.pack("=I", len(raw)) + raw)
    hdr = b""
    while len(hdr) < 4:
        chunk = sock.recv(4 - len(hdr))
        if not chunk:
            raise RuntimeError("greetd socket closed")
        hdr += chunk
    (length,) = struct.unpack("=I", hdr)
    body = b""
    while len(body) < length:
        chunk = sock.recv(length - len(body))
        if not chunk:
            raise RuntimeError("greetd socket truncated")
        body += chunk
    return json.loads(body.decode("utf-8"))


def authenticate_greetd(
    username: str,
    password: str,
    session_cmd: list[str],
    session_env: list[str] | None = None,
) -> tuple[bool, str]:
    sock_path = os.environ.get("GREETD_SOCK")
    if not sock_path:
        return False, "GREETD_SOCK not set"
    if session_env is None:
        session_env = [
            "LANG=C.UTF-8",
            "XDG_SESSION_TYPE=wayland",
            "XDG_CURRENT_DESKTOP=labwc:wlroots",
            "MOZ_ENABLE_WAYLAND=1",
        ]
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.connect(sock_path)
        try:
            resp = greetd_roundtrip(s, {"type": "create_session", "username": username})
            while resp.get("type") == "auth_message":
                msg_type = resp.get("auth_message_type", "")
                reply = password if msg_type in ("secret", "visible") else ""
                resp = greetd_roundtrip(
                    s, {"type": "post_auth_message_response", "response": reply}
                )
            if resp.get("type") != "success":
                desc = resp.get("description", "Authentication failed")
                greetd_roundtrip(s, {"type": "cancel_session"})
                return False, desc

            start_resp = greetd_roundtrip(
                s,
                {
                    "type": "start_session",
                    "cmd": session_cmd,
                    "env": session_env,
                },
            )
            if start_resp.get("type") == "success":
                return True, "OK"
            desc = start_resp.get("description", "Failed to start session")
            greetd_roundtrip(s, {"type": "cancel_session"})
            return False, desc
        except Exception as exc:
            try:
                greetd_roundtrip(s, {"type": "cancel_session"})
            except Exception:
                pass
            return False, str(exc)


def run_auth_stdio() -> int:
    """Authenticate a single JSON request over stdin."""
    try:
        raw_line = sys.stdin.readline()
        if not raw_line:
            print(json.dumps({"ok": False, "message": "Empty auth request"}), flush=True)
            return 1
        req = json.loads(raw_line)
        username = str(req.get("user") or "").strip()
        password = str(req.get("password") or "")
        cmd = list(req.get("cmd") or ["/usr/bin/transformer-session"])
        env = req.get("env")
        if env is not None:
            env = [str(x) for x in env]
        if not username or not password:
            print(
                json.dumps({"ok": False, "message": "Username and password required"}),
                flush=True,
            )
            return 1
        ok, msg = authenticate_greetd(username, password, cmd, env)
        print(json.dumps({"ok": ok, "message": msg}), flush=True)
        return 0 if ok else 1
    except Exception as exc:
        print(json.dumps({"ok": False, "message": str(exc)}), flush=True)
        return 1


if __name__ == "__main__":
    sys.exit(run_auth_stdio())
