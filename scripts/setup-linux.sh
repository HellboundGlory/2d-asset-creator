#!/usr/bin/env bash
# Installs Krita 6.0.4 (AppImage), the krita-mcp plugin with its native helper, and the
# Rigby2D MCP server. Safe to run again: finished steps are skipped.
set -euo pipefail

KRITA_VERSION=6.0.4
KRITA_URL="https://download.kde.org/stable/krita/${KRITA_VERSION}/krita-${KRITA_VERSION}-x86_64.AppImage"
KRITA_SHA256=4ec9a45892308134b0ff5410f30aa9e68ae58d0dae5fb122666cfd27dfd6de9f
KRITA_MCP_TAG=v1.8.1
QT_VERSION=6.8.0
AQT_VERSION=3.3.0
RIGBY_VERSION=0.5.1
RIGBY_MCPB_URL="https://github.com/jaisurya-dev-art/rigby2d/releases/download/v${RIGBY_VERSION}/Rigby2D-AI-${RIGBY_VERSION}.mcpb"
RIGBY_MCPB_SHA256=5fc015890fe5f8a31dfe806cff9e40aec62b10fe7fd283ce843fa7923491e0c6

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
A2D_HOME="$(realpath -m "${A2D_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/2d-asset-creator}")"
KRITA_APPIMAGE="${KRITA_APPIMAGE:-$A2D_HOME/krita-${KRITA_VERSION}-x86_64.AppImage}"
KRITA_MCP_DIR="${KRITA_MCP_DIR:-$A2D_HOME/krita-mcp}"
RIGBY_MCP_DIR="${RIGBY_MCP_DIR:-$A2D_HOME/rigby2d-mcp/$RIGBY_VERSION}"
SDK_DIR="$A2D_HOME/krita-${KRITA_VERSION}-sdk"
QT_DIR="$A2D_HOME/qt/$QT_VERSION/gcc_64"

step() { printf '\n== %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
json_field() { python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$1" "$2"; }

usage() {
  cat <<EOF
Usage: scripts/setup-linux.sh [--skip-rigby] [--skip-plugin-install] [--rebuild]

Installs into \$A2D_HOME (now: $A2D_HOME). Override any of these with environment variables:
  A2D_HOME, KRITA_APPIMAGE, KRITA_MCP_DIR, RIGBY_MCP_DIR
The Krita plugin goes into Krita's profile (\$XDG_DATA_HOME/krita, \$XDG_CONFIG_HOME/kritarc).
Network: download.kde.org, github.com, api.github.com and raw.githubusercontent.com (Krita headers),
download.qt.io (Qt headers), pypi.org (aqtinstall).
EOF
}

skip_rigby=0 skip_plugin=0 rebuild=0
for arg in "$@"; do
  case "$arg" in
    --skip-rigby) skip_rigby=1 ;;
    --skip-plugin-install) skip_plugin=1 ;;
    --rebuild) rebuild=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; die "unknown option $arg" ;;
  esac
done

mkdir -p "$A2D_HOME"

step "Checking this machine"
[ "$(uname -s)" = Linux ] || die "The native helper is Linux only. See README.md for other systems."
[ "$(uname -m)" = x86_64 ] || die "Krita's AppImage is x86_64 only."
needed=(curl git cmake c++ python3 objdump readelf ldd strings sha256sum pgrep)
[ -f "$QT_DIR/lib/cmake/Qt6/Qt6Config.cmake" ] || needed+=(uvx)
[ $skip_rigby -eq 1 ] || needed+=(node unzip)
missing=()
for cmd in "${needed[@]}"; do
  command -v "$cmd" >/dev/null || missing+=("$cmd")
done
[ ${#missing[@]} -eq 0 ] || die "Missing commands: ${missing[*]} (uvx comes from https://docs.astral.sh/uv/)"
if [ $skip_rigby -eq 0 ]; then
  node_major=$(node -p 'process.versions.node.split(".")[0]')
  [ "$node_major" -ge 20 ] || die "Rigby2D MCP needs Node.js 20 or newer (found $(node --version))."
fi

absent=()
for h in /usr/include/KF6/KI18n/klocalizedstring.h /usr/include/KF6/KConfigCore/kconfiggroup.h \
         /usr/include/boost/operators.hpp; do
  [ -f "$h" ] || absent+=("$h")
done
[ -f /usr/include/eigen3/Eigen/Sparse ] || [ -f /usr/include/Eigen/Sparse ] || absent+=("Eigen/Sparse")
if [ ${#absent[@]} -gt 0 ]; then
  printf 'Missing build headers:\n'; printf '  %s\n' "${absent[@]}"
  cat <<'EOF'
Install them with your package manager, then run this script again:
  Fedora:          sudo dnf install kf6-ki18n-devel kf6-kconfig-devel boost-devel eigen3-devel cmake gcc-c++
  Debian / Ubuntu: sudo apt install libkf6i18n-dev libkf6config-dev libboost-dev libeigen3-dev cmake g++
  Arch:            sudo pacman -S ki18n kconfig boost eigen cmake gcc
(Only the Fedora names are tested.)
EOF
  exit 1
fi
if [ $skip_plugin -eq 0 ] && pgrep -x krita >/dev/null; then
  die "Krita is running. Close it first: the plugin installer edits kritarc, which Krita rewrites on exit."
fi
echo "OK tools and headers"

step "Krita $KRITA_VERSION AppImage"
mkdir -p "$(dirname "$KRITA_APPIMAGE")"
if [ ! -f "$KRITA_APPIMAGE" ]; then
  curl -fSL --retry 5 -o "$KRITA_APPIMAGE.part" "$KRITA_URL"
  mv "$KRITA_APPIMAGE.part" "$KRITA_APPIMAGE"
fi
echo "$KRITA_SHA256  $KRITA_APPIMAGE" | sha256sum -c - >/dev/null || die "Checksum mismatch: $KRITA_APPIMAGE"
chmod +x "$KRITA_APPIMAGE"
echo "OK $KRITA_APPIMAGE"

step "Unpacking the AppImage (build libraries, and a FUSE-free way to run it)"
if [ ! -f "$SDK_DIR/squashfs-root/usr/lib/libkritaui.so" ]; then
  rm -rf "$SDK_DIR"; mkdir -p "$SDK_DIR"
  (cd "$SDK_DIR" && "$KRITA_APPIMAGE" --appimage-extract >/dev/null)
fi
KRITA_LIB="$SDK_DIR/squashfs-root/usr/lib"
appimage_qt=$( (strings "$KRITA_LIB/libQt6Core.so.6" | sed -n 's/^Qt \(6\.[0-9.]*\) .*/\1/p' | head -n1) || true)
[ "$appimage_qt" = "$QT_VERSION" ] || die "The AppImage bundles Qt '${appimage_qt:-unknown}', this script expects $QT_VERSION."
echo "OK Qt $appimage_qt in the AppImage"

step "Qt $QT_VERSION headers (to match the AppImage)"
if [ ! -f "$QT_DIR/lib/cmake/Qt6/Qt6Config.cmake" ]; then
  # aqt writes aqtinstall.log into the working folder.
  (cd "$A2D_HOME" && uvx --from "aqtinstall==$AQT_VERSION" aqt install-qt linux desktop "$QT_VERSION" linux_gcc_64 \
    -O "$A2D_HOME/qt" --archives qtbase icu)
fi
echo "OK $QT_DIR"

step "krita-mcp $KRITA_MCP_TAG"
if [ ! -d "$KRITA_MCP_DIR/.git" ]; then
  git -c advice.detachedHead=false clone -q --branch "$KRITA_MCP_TAG" \
    https://github.com/thuanlm215/krita-mcp.git "$KRITA_MCP_DIR"
fi
tag_commit=$(git -C "$KRITA_MCP_DIR" rev-parse -q --verify "$KRITA_MCP_TAG^{commit}" || true)
[ -n "$tag_commit" ] && [ "$(git -C "$KRITA_MCP_DIR" rev-parse HEAD)" = "$tag_commit" ] \
  || die "$KRITA_MCP_DIR is not at $KRITA_MCP_TAG. Move it aside or check out $KRITA_MCP_TAG."
patch_file="$SKILL_DIR/patches/krita-mcp-1.8.1-helper-version-check.patch"
if git -C "$KRITA_MCP_DIR" apply --check "$patch_file" 2>/dev/null; then
  git -C "$KRITA_MCP_DIR" apply "$patch_file"
  echo "Applied the helper version-check patch"
elif git -C "$KRITA_MCP_DIR" apply -R --check "$patch_file" 2>/dev/null; then
  echo "Helper version-check patch already applied"
else
  echo "WARNING: the version-check patch does not apply. Check native_commands.py by hand."
fi

step "Native helper build"
manifest="$KRITA_MCP_DIR/pykrita/krita_mcp/native_manifest.json"
helper_ok() {
  [ -f "$manifest" ] || return 1
  local file sum
  file=$(json_field "$manifest" file) && sum=$(json_field "$manifest" sha256) || return 1
  echo "$sum  $KRITA_MCP_DIR/pykrita/krita_mcp/$file" | sha256sum -c - >/dev/null 2>&1
}
if [ $rebuild -eq 1 ] || ! helper_ok; then
  shim="$A2D_HOME/cmake/KF6I18n"
  mkdir -p "$shim"
  {
    echo "# Links the helper to the AppImage's own KF6I18n. The system package's CMake files want a newer Qt."
    echo "if(NOT TARGET KF6::I18n)"
    echo "  add_library(KF6::I18n SHARED IMPORTED)"
    echo "  set_target_properties(KF6::I18n PROPERTIES"
    echo "    IMPORTED_LOCATION \"$KRITA_LIB/libKF6I18n.so.6\""
    echo "    INTERFACE_INCLUDE_DIRECTORIES \"/usr/include/KF6/KI18n\")"
    echo "endif()"
    echo "set(KF6I18n_FOUND TRUE)"
  } >"$shim/KF6I18nConfig.cmake"
  build="$KRITA_MCP_DIR/native/build"
  rm -rf "$build/CMakeCache.txt" "$build/CMakeFiles"
  export CMAKE_PREFIX_PATH="$QT_DIR" CMAKE_LIBRARY_PATH="$KRITA_LIB"
  cmake -S "$KRITA_MCP_DIR/native" -B "$build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_SKIP_RPATH=ON \
    -DKF6I18n_DIR="$shim" -DQt6_DIR="$QT_DIR/lib/cmake/Qt6" >"$A2D_HOME/helper-build.log" 2>&1 \
    || die "CMake failed; see $A2D_HOME/helper-build.log"
  (cd "$KRITA_MCP_DIR" && python3 build_native.py) >>"$A2D_HOME/helper-build.log" 2>&1 \
    || die "Helper build failed; see $A2D_HOME/helper-build.log"
  helper_ok || die "The helper build left no valid native_manifest.json"
else
  echo "Helper already built (use --rebuild to build it again)"
fi
helper="$KRITA_MCP_DIR/pykrita/krita_mcp/$(json_field "$manifest" file)"

step "Checking the helper links against the AppImage"
links=$(LD_LIBRARY_PATH="$KRITA_LIB" ldd -r "$helper" 2>&1) || die "ldd could not read $helper"
if grep -q -E 'undefined symbol|not found' <<<"$links"; then
  grep -E 'undefined symbol|not found' <<<"$links" | head -n 5 >&2
  die "The helper does not resolve against the AppImage libraries"
fi
dynamic=$(readelf -d "$helper")
if grep -q -E 'RPATH|RUNPATH' <<<"$dynamic"; then die "The helper has a library search path baked in"; fi
newest_qt=$( (objdump -T "$helper" | grep -o 'Qt_6\.[0-9]*' | sort -t. -k2 -n | tail -n1) || true)
[ -z "$newest_qt" ] || [ "${newest_qt#Qt_6.}" -le "$(echo "$QT_VERSION" | cut -d. -f2)" ] \
  || die "The helper needs $newest_qt but the AppImage has Qt $QT_VERSION"
echo "OK $(basename "$helper"): every symbol resolves, no RUNPATH, newest Qt symbol ${newest_qt:-none}"

if [ $skip_plugin -eq 0 ]; then
  step "Installing the plugin into Krita's profile"
  data="${XDG_DATA_HOME:-$HOME/.local/share}/krita"
  config="${XDG_CONFIG_HOME:-$HOME/.config}/kritarc"
  if diff -rq -x __pycache__ "$KRITA_MCP_DIR/pykrita/krita_mcp" "$data/pykrita/krita_mcp" >/dev/null 2>&1 \
    && grep -q '^enable_krita_mcp=true' "$config" 2>/dev/null; then
    echo "Plugin already installed and enabled in $data"
  else
    backup="$A2D_HOME/backups/$(date +%Y%m%d-%H%M%S)"
    if [ -f "$config" ] || [ -d "$data/pykrita" ]; then
      mkdir -p "$backup"
      [ ! -f "$config" ] || cp -a "$config" "$backup/"
      [ ! -d "$data/pykrita" ] || cp -a "$data/pykrita" "$backup/"
      echo "Backed up kritarc and pykrita to $backup"
    fi
    (cd "$KRITA_MCP_DIR" && python3 mcp_server.py install)
  fi
fi

if [ $skip_rigby -eq 0 ]; then
  step "Rigby2D MCP server $RIGBY_VERSION"
  if [ ! -f "$RIGBY_MCP_DIR/server/src/mcp/server.js" ]; then
    mkdir -p "$RIGBY_MCP_DIR"
    curl -fSL --retry 5 -o "$RIGBY_MCP_DIR.mcpb" "$RIGBY_MCPB_URL"
    echo "$RIGBY_MCPB_SHA256  $RIGBY_MCP_DIR.mcpb" | sha256sum -c - >/dev/null \
      || die "Checksum mismatch: $RIGBY_MCP_DIR.mcpb"
    unzip -q -o "$RIGBY_MCP_DIR.mcpb" -d "$RIGBY_MCP_DIR"
    rm -f "$RIGBY_MCP_DIR.mcpb"
  fi
  echo "OK $(node "$RIGBY_MCP_DIR/server/src/mcp/server.js" --version)"
fi

# One KEY=value per line, read line by line by the other scripts (never sourced), so paths may contain spaces.
printf 'KRITA_APPIMAGE=%s\nKRITA_MCP_DIR=%s\nRIGBY_MCP_DIR=%s\n' \
  "$(realpath "$KRITA_APPIMAGE")" "$(realpath "$KRITA_MCP_DIR")" "$(realpath -m "$RIGBY_MCP_DIR")" >"$A2D_HOME/paths.env"

step "Done"
cat <<EOF
Paths saved in $A2D_HOME/paths.env.
Next:
  1. Add the MCP servers to a project:  python3 $SKILL_DIR/scripts/add_mcp_servers.py /path/to/project
  2. Start Krita:                       $SKILL_DIR/scripts/start-krita.sh
  3. Check everything:                  $SKILL_DIR/scripts/doctor.sh
EOF
