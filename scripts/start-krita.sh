#!/usr/bin/env bash
# Starts Krita 6.0.4 for krita-mcp.
#   start-krita.sh                      opens the normal Krita window with your profile
#   start-krita.sh --headless DIR       runs Krita with no window (Xvfb) and a private profile in DIR,
#                                       for servers, CI and smoke tests; prints the env the MCP server needs
#   start-krita.sh --stop DIR           stops a headless Krita started with that DIR
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
A2D_HOME="${A2D_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/2d-asset-creator}"
# paths.env holds KEY=value lines from setup-linux.sh; variables already set in the environment win.
load_paths() {
  local line key
  [ -f "$A2D_HOME/paths.env" ] || return 0
  while IFS= read -r line; do
    key=${line%%=*}
    case "$key" in
      KRITA_APPIMAGE|KRITA_MCP_DIR|RIGBY_MCP_DIR) [ -n "${!key:-}" ] || printf -v "$key" '%s' "${line#*=}" ;;
    esac
  done <"$A2D_HOME/paths.env"
}
load_paths
KRITA_APPIMAGE="${KRITA_APPIMAGE:-$A2D_HOME/krita-6.0.4-x86_64.AppImage}"
KRITA_MCP_DIR="${KRITA_MCP_DIR:-$A2D_HOME/krita-mcp}"
EXTRACTED="$A2D_HOME/krita-6.0.4-sdk/squashfs-root"
[ -x "$KRITA_APPIMAGE" ] || { echo "No Krita AppImage at $KRITA_APPIMAGE. Run $SKILL_DIR/scripts/setup-linux.sh" >&2; exit 1; }

alive() { [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null; }

# Runs Krita from the tree setup-linux.sh extracted, so no FUSE is needed (as krita-mcp's CI does).
run_krita() {
  if [ -x "$EXTRACTED/AppRun" ]; then
    PYTHONHOME="$EXTRACTED/usr" \
    PYTHONPATH="$EXTRACTED/usr/lib/python3.13:$EXTRACTED/usr/lib/python3.13/site-packages:$EXTRACTED/usr/lib/krita-python-libs" \
      "$EXTRACTED/AppRun" "$@"
  else
    "$KRITA_APPIMAGE" "$@"
  fi
}

# Returns 1 and keeps the pid files when a process is still running afterwards.
stop_dir() {
  local dir=$1 pid left=0
  pid=$(cat "$dir/krita.pid" 2>/dev/null || true)
  if alive "$pid"; then
    # The pid file names the session leader this script started; only signal it if it still leads its group.
    if [ "$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')" = "$pid" ]; then
      kill -TERM -- "-$pid" 2>/dev/null || true
      for _ in $(seq 1 50); do alive "$pid" || break; sleep 0.2; done
      alive "$pid" && kill -KILL -- "-$pid" 2>/dev/null || true
      sleep 0.2
    fi
    alive "$pid" && left=1
  fi
  pid=$(cat "$dir/xvfb.pid" 2>/dev/null || true)
  # A live pid that is not Xvfb is a reused number from a stale file, not ours.
  if alive "$pid" && [ "$(ps -o comm= -p "$pid" 2>/dev/null)" = Xvfb ]; then
    kill "$pid" 2>/dev/null || true
    for _ in $(seq 1 25); do alive "$pid" || break; sleep 0.2; done
    alive "$pid" && kill -KILL "$pid" 2>/dev/null && sleep 0.2
    alive "$pid" && left=1
  fi
  if [ $left -eq 1 ]; then
    echo "Could not stop everything in $dir; check the PIDs in krita.pid and xvfb.pid" >&2
    return 1
  fi
  rm -f "$dir/krita.pid" "$dir/xvfb.pid" "$dir/state/krita_mcp_bridge.json"
}

case "${1:-}" in
  "")
    run_krita --nosplash
    ;;
  --stop)
    dir="$(realpath "${2:?usage: start-krita.sh --stop DIR}")"
    stop_dir "$dir" || exit 1
    echo "Stopped headless Krita in $dir"
    ;;
  --headless)
    dir="${2:?usage: start-krita.sh --headless DIR}"
    mkdir -p "$dir"; dir="$(realpath "$dir")"
    if alive "$(cat "$dir/krita.pid" 2>/dev/null || true)"; then
      echo "A headless Krita is already running in $dir (stop it with --stop $dir)" >&2; exit 1
    fi
    stop_dir "$dir" || exit 1  # clears an Xvfb left by a Krita that died without --stop
    command -v Xvfb >/dev/null || { echo "Install Xvfb (Fedora: xorg-x11-server-Xvfb, Debian: xvfb)" >&2; exit 1; }
    command -v dbus-run-session >/dev/null || { echo "dbus-run-session is missing" >&2; exit 1; }
    for sub in config data cache run tmp state home; do mkdir -p "$dir/$sub"; done
    chmod 700 "$dir/run"
    rm -f "$dir/state/krita_mcp_bridge.json"
    export XDG_CONFIG_HOME="$dir/config" XDG_DATA_HOME="$dir/data" XDG_CACHE_HOME="$dir/cache" \
      XDG_RUNTIME_DIR="$dir/run" TMPDIR="$dir/tmp" KRITA_MCP_STATE_DIR="$dir/state" QT_QPA_PLATFORM=xcb
    unset WAYLAND_DISPLAY
    if ! diff -rq -x __pycache__ "$KRITA_MCP_DIR/pykrita/krita_mcp" "$XDG_DATA_HOME/krita/pykrita/krita_mcp" >/dev/null 2>&1; then
      (cd "$KRITA_MCP_DIR" && python3 mcp_server.py install >/dev/null)
    fi
    # The plugin starts its bridge on launch; Xvfb has no OpenGL canvas.
    cat >"$XDG_CONFIG_HOME/kritarc" <<'EOF'
[python]
enable_krita_mcp=true
[krita_mcp]
autostart=true
[General]
HideWelcomeScreen=true
EOF
    printf '[General]\nOpenGLRenderer=none\n' >"$XDG_CONFIG_HOME/kritadisplayrc"
    fifo="$dir/run/xvfb-display"
    rm -f "$fifo"; mkfifo "$fifo"
    Xvfb -displayfd 3 -screen 0 1280x900x24 -nolisten tcp 3>"$fifo" </dev/null >/dev/null 2>"$dir/xvfb.log" &
    echo "$!" >"$dir/xvfb.pid"
    display=""
    read -r -t 20 display <"$fifo" || true
    rm -f "$fifo"
    if [ -z "$display" ]; then
      stop_dir "$dir" || true; echo "Xvfb did not start; see $dir/xvfb.log" >&2; exit 1
    fi
    export DISPLAY=":$display"
    launcher="$dir/run/launch-krita.sh"
    { echo '#!/usr/bin/env bash'
      printf 'EXTRACTED=%q\nKRITA_APPIMAGE=%q\n' "$EXTRACTED" "$KRITA_APPIMAGE"
      declare -f run_krita
      echo 'run_krita --nosplash'; } >"$launcher"
    chmod +x "$launcher"
    HOME="$dir/home" setsid dbus-run-session -- "$launcher" </dev/null >"$dir/krita.log" 2>&1 &
    echo "$!" >"$dir/krita.pid"
    for _ in $(seq 1 450); do
      [ -f "$dir/state/krita_mcp_bridge.json" ] && break
      if ! alive "$(cat "$dir/krita.pid")"; then
        stop_dir "$dir" || true; echo "Krita exited; see $dir/krita.log" >&2; exit 1
      fi
      sleep 0.2
    done
    if [ ! -f "$dir/state/krita_mcp_bridge.json" ]; then
      stop_dir "$dir" || true; echo "The MCP bridge did not start within 90 s; see $dir/krita.log" >&2; exit 1
    fi
    cat <<EOF
Headless Krita is running (display :$display). Give the krita MCP server this env:
  KRITA_MCP_STATE_DIR=$dir/state
Stop it with: $SKILL_DIR/scripts/start-krita.sh --stop $dir
EOF
    ;;
  *)
    echo "usage: start-krita.sh [--headless DIR | --stop DIR]" >&2; exit 1
    ;;
esac
