#!/usr/bin/env bash
# Checks the Krita, krita-mcp and Rigby2D setup. Prints PASS/WARN/FAIL lines; exits 1 on any FAIL.
# With Krita running (or KRITA_MCP_STATE_DIR pointing at a headless one) it also checks the live bridge.
set -uo pipefail

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
RIGBY_MCP_DIR="${RIGBY_MCP_DIR:-$A2D_HOME/rigby2d-mcp/0.5.1}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
# A headless Krita from start-krita.sh keeps its whole profile next to its state folder.
if [ -n "${KRITA_MCP_STATE_DIR:-}" ] && [ -d "$KRITA_MCP_STATE_DIR/../data" ]; then
  DATA_HOME="$(realpath "$KRITA_MCP_STATE_DIR/../data")"
  CONFIG_HOME="$(realpath "$KRITA_MCP_STATE_DIR/../config")"
fi
PLUGIN="$DATA_HOME/krita/pykrita/krita_mcp"
KRITARC="$CONFIG_HOME/kritarc"
fails=0
pass() { echo "PASS $*"; }
warn() { echo "WARN $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }
json_field() { python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$1" "$2" 2>/dev/null; }

if [ -x "$KRITA_APPIMAGE" ]; then
  if echo "4ec9a45892308134b0ff5410f30aa9e68ae58d0dae5fb122666cfd27dfd6de9f  $KRITA_APPIMAGE" | sha256sum -c - >/dev/null 2>&1; then
    pass "Krita 6.0.4 AppImage: $KRITA_APPIMAGE"
  else
    fail "$KRITA_APPIMAGE is not the official Krita 6.0.4 AppImage"
  fi
else
  fail "No Krita AppImage at $KRITA_APPIMAGE (run scripts/setup-linux.sh)"
fi

if [ -f "$KRITA_MCP_DIR/mcp_server.py" ]; then
  tag=$(git -C "$KRITA_MCP_DIR" describe --tags --exact-match HEAD 2>/dev/null || echo "unknown version")
  if [ "$tag" = v1.8.1 ]; then pass "krita-mcp server v1.8.1: $KRITA_MCP_DIR"
  else warn "krita-mcp at $KRITA_MCP_DIR is $tag; this skill is tested with v1.8.1"; fi
else
  fail "No krita-mcp at $KRITA_MCP_DIR"
fi

if [ -d "$PLUGIN" ]; then
  manifest="$PLUGIN/native_manifest.json"
  if [ -f "$manifest" ]; then
    file=$(json_field "$manifest" file)
    want=$(json_field "$manifest" sha256)
    have=$(sha256sum "$PLUGIN/${file:-none}" 2>/dev/null | cut -d' ' -f1)
    if [ -n "$want" ] && [ "$have" = "$want" ]; then pass "Native helper installed: $file"
    else fail "Native helper is missing, changed, or its manifest is unreadable ($manifest)"; fi
  else
    fail "Plugin has no native helper (drawing, brushes, selections and undo will be unsupported)"
  fi
  if grep -q 'version().partition(" ")\[0\] != "6.0.4"' "$PLUGIN/native_commands.py"; then
    pass "Helper version check accepts the official AppImage"
  else
    fail "Helper version check is unpatched: the official AppImage reports '6.0.4 (git 57db7cd)'"
  fi
  if [ -d "$KRITA_MCP_DIR/pykrita/krita_mcp" ] \
    && ! diff -rq -x __pycache__ "$PLUGIN" "$KRITA_MCP_DIR/pykrita/krita_mcp" >/dev/null 2>&1; then
    warn "Installed plugin differs from $KRITA_MCP_DIR; rerun its installer so server and plugin match"
  fi
else
  fail "krita-mcp plugin not installed in $PLUGIN"
fi
grep -q '^enable_krita_mcp=true' "$KRITARC" 2>/dev/null && pass "MCP Bridge enabled in $KRITARC" \
  || warn "MCP Bridge not enabled in $KRITARC (Settings > Configure Krita > Python Plugin Manager)"

if command -v node >/dev/null && [ "$(node -p 'process.versions.node.split(".")[0]')" -ge 20 ]; then
  if [ -f "$RIGBY_MCP_DIR/server/src/mcp/server.js" ]; then
    pass "Rigby2D MCP $(node "$RIGBY_MCP_DIR/server/src/mcp/server.js" --version 2>&1 | head -n1): $RIGBY_MCP_DIR"
  else
    fail "No Rigby2D MCP server at $RIGBY_MCP_DIR"
  fi
else
  fail "Node.js 20 or newer is needed for the Rigby2D MCP server"
fi

if [ -f "$KRITA_MCP_DIR/mcp_server.py" ]; then
  if status=$(python3 "$KRITA_MCP_DIR/mcp_server.py" --call status 2>&1); then
    version=$(printf '%s' "$status" | python3 -c 'import json,sys;print(json.load(sys.stdin)["krita_version"])')
    [ "${version%% *}" = 6.0.4 ] && pass "Live bridge: Krita $version" || fail "Live bridge: Krita $version (helper needs 6.0.4)"
    caps=$(python3 "$KRITA_MCP_DIR/mcp_server.py" --call workflow_capabilities 2>/dev/null)
    if printf '%s' "$caps" | python3 -c 'import json,sys;sys.exit(0 if json.load(sys.stdin)["native_helper"]["available"] else 1)' 2>/dev/null; then
      pass "Live bridge: native helper available"
    else
      fail "Live bridge: native helper unavailable: $(printf '%s' "$caps" | python3 -c 'import json,sys;print(json.load(sys.stdin)["native_helper"].get("reason"))' 2>/dev/null)"
    fi
  else
    warn "Live bridge not reachable, so it was not checked: $(printf '%s' "$status" | head -n1)"
    warn "  Start Krita with scripts/start-krita.sh; for a headless one, set KRITA_MCP_STATE_DIR=<dir>/state"
  fi
fi

[ $fails -eq 0 ] && echo "RESULT: OK" || echo "RESULT: $fails problem(s)"
[ $fails -eq 0 ]
