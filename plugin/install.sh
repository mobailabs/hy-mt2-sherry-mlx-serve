#!/usr/bin/env bash
# Install hy_mt2_sherry into mlx-serve on this machine, from the source in this folder.
#
#   ./install.sh                    # auto-detect mlx-serve, build, install
#   ./install.sh --check-only       # build + conformance, do not install
#   MLX_SERVE=/path/to/mlx-serve ./install.sh
#
# Needs Apple Silicon macOS, Xcode command line tools, curl, and the mlx-serve app or CLI
# (a release that ships the plugin kit: 26.11.x or newer).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

say() { printf '\n[hy_mt2] %s\n' "$*"; }
die() { printf '\n[hy_mt2] ERROR: %s\n' "$*" >&2; exit 1; }

# ── layout ──
# Where the plugin lives and where the kit and Zig go: the repo (plugin/ beside this file), the plugin folder
# itself, or a catalog checkout (plugins/hy_mt2_sherry in it).
# `here` is where this script sits: plugin/ in this repo, the plugin folder in a flat bundle, or
# plugins/<name> in a mlx-serve catalog checkout. The repo root = the plugin folder's parent when that parent
# holds this repo's README; otherwise the plugin folder itself is the root (the kit and Zig go beside it).
if [ -f "$here/plugin.zig" ] && [ -f "$here/INSTALL.md" ] && [ -f "$(dirname "$here")/plugin/plugin.zig" ]; then
  PLUGIN_DIR="$here"
  KIT_HOME="$(dirname "$here")"
elif [ -f "$here/plugin.zig" ]; then
  PLUGIN_DIR="$here"
  KIT_HOME="$here"
else
  PLUGIN_DIR="$here/plugins/hy_mt2_sherry"
  KIT_HOME="$here"
fi
[ -f "$PLUGIN_DIR/plugin.zig" ] || die "no plugin.zig under $here"
ZIG_DIR="$KIT_HOME/.zig-toolchain"

# ── platform ──
[ "$(uname -s)" = Darwin ] || die "macOS only (this is $(uname -s))"
[ "$(uname -m)" = arm64 ] || die "Apple Silicon only (this is $(uname -m)); the STQ kernels use Apple Metal"

# ── find mlx-serve ──
if [ -z "${MLX_SERVE:-}" ]; then
  if command -v mlx-serve >/dev/null 2>&1; then
    MLX_SERVE="$(command -v mlx-serve)"
  elif [ -x /Applications/MLX-Serve.app/Contents/MacOS/mlx-serve ]; then
    MLX_SERVE=/Applications/MLX-Serve.app/Contents/MacOS/mlx-serve
  else
    die "mlx-serve not found. Install the app (https://github.com/ddalcu/mlx-serve/releases) or set MLX_SERVE=/path/to/mlx-serve"
  fi
fi
[ -x "$MLX_SERVE" ] || die "not executable: $MLX_SERVE"

version_line="$("$MLX_SERVE" --version 2>&1 | grep -E '^mlx-serve [0-9]' | head -1 || true)"
[ -n "$version_line" ] || die "$MLX_SERVE did not report a version"
SERVER_VERSION="${version_line#mlx-serve }"
SERVER_VERSION="${SERVER_VERSION%% *}"
say "mlx-serve $SERVER_VERSION at $MLX_SERVE"

# The kit the plugin builds against must carry the same MLX pin as this server. The release asset is keyed by
# version, so read the version off the binary rather than guessing.
# `mlx-serve plugin` with no subcommand prints its usage and exits 1, so read the output, not the status.
plugin_usage="$("$MLX_SERVE" plugin 2>&1 || true)"
case "$plugin_usage" in
  *"plugin install"*) say "plugin support: yes" ;;
  *) die "this mlx-serve ($SERVER_VERSION) has no 'plugin' command: use 26.11.1 or newer" ;;
esac

# ── zig ──
# Pinned toolchain: an outside plugin must be built with the same Zig the kit targets.
ZIG_VERSION=0.17.0
if [ -x "$ZIG_DIR/zig" ]; then
  ZIG="$ZIG_DIR/zig"
elif command -v zig >/dev/null 2>&1 && zig version 2>/dev/null | grep -q "^$ZIG_VERSION"; then
  ZIG="$(command -v zig)"
else
  case "$(uname -m)" in
    arm64) ZIG_ARCH=aarch64-macos ;;
    *) die "unsupported arch for zig download" ;;
  esac
  if [ ! -x "$ZIG_DIR/zig" ]; then
    say "fetching Zig $ZIG_VERSION (pinned)"
    mkdir -p "$ZIG_DIR"
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    curl -fsSL "https://ziglang.org/download/$ZIG_VERSION/zig-$ZIG_ARCH-$ZIG_VERSION.tar.xz" -o "$tmp/zig.tar.xz" \
      || die "could not download Zig; install $ZIG_VERSION by hand and re-run"
    tar -xJf "$tmp/zig.tar.xz" -C "$tmp"
    cp -R "$tmp/zig-$ZIG_ARCH-$ZIG_VERSION/." "$ZIG_DIR/"
  fi
  ZIG="$ZIG_DIR/zig"
fi
say "zig $("$ZIG" version)"

# ── kit ──
KIT_DIR="$KIT_HOME/kit"
# The kit that matches the server wins; a KIT_VERSION in the bundle is only a fallback.
if [ -f "$here/KIT_VERSION" ]; then
  KIT_VERSION="$(tr -d '[:space:]' < "$here/KIT_VERSION")"
else
  KIT_VERSION="$SERVER_VERSION"
fi
say "kit target: $KIT_VERSION"

if [ ! -f "$KIT_DIR/mlx.version" ]; then
  # Try the release asset for the server's own version first (that is the kit whose pin matches), then the
  # KIT_VERSION in this folder. GitHub serves these assets with frequent 504s: retry.
  ok=no
  for v in "$SERVER_VERSION" "$KIT_VERSION"; do
    url="https://github.com/ddalcu/mlx-serve/releases/download/v$v/mlx-serve-plugin-kit-$v.tar.gz"
    for attempt in 1 2 3 4 5; do
      say "downloading kit $v (attempt $attempt)"
      tmp="$(mktemp -d)"
      if curl -fsSL --max-time 120 "$url" -o "$tmp/kit.tgz" 2>/dev/null; then
        mkdir -p "$tmp/x"
        if tar -xzf "$tmp/kit.tgz" -C "$tmp/x" 2>/dev/null; then
          d="$tmp/x/mlx-serve-plugin-kit-$v"
          if [ -f "$d/mlx.version" ]; then
            rm -rf "$KIT_DIR"
            mkdir -p "$KIT_HOME"
            cp -R "$d" "$KIT_DIR"
            echo "$v" > "$KIT_DIR/.version"
            ok=yes
          fi
        fi
      fi
      rm -rf "$tmp"
      [ "$ok" = yes ] && break 2
      sleep 4
    done
  done
  [ "$ok" = yes ] || die "could not download the plugin kit.

Point this installer at a kit you already have:
  MLX_SERVE_KIT=/path/to/mlx-serve-plugin-kit-<version> ./install.sh

Or build one from the server's source:
  git clone --recurse-submodules https://github.com/ddalcu/mlx-serve && cd mlx-serve && zig build kit
  (needs the Metal toolchain: xcodebuild -downloadComponent MetalToolchain)"
fi
[ -f "$KIT_DIR/mlx.version" ] || die "no kit at $KIT_DIR"

kit_pin="$(cat "$KIT_DIR/mlx.version")"
server_pin="$(strings "$MLX_SERVE" 2>/dev/null | grep -E '^mlx=.*target=' | head -1 || true)"
if [ -n "$server_pin" ]; then
  if [ "$kit_pin" != "$server_pin" ]; then
    say "WARNING: kit pin differs from this server's"
    say "  kit:    $kit_pin"
    say "  server: $server_pin"
    say "  The plugin will build, but mlx-serve will refuse it at load. Use the kit of the server's release:"
    say "    MLX_SERVE_KIT=<kit for $SERVER_VERSION> ./install.sh"
  else
    say "pin matches the server: $kit_pin"
  fi
fi

# ── build ──
export MLX_SERVE_KIT="${MLX_SERVE_KIT:-$KIT_DIR}"
export PATH="$(dirname "$MLX_SERVE"):$PATH"
cd "$PLUGIN_DIR"

# build.zig.zon names the kit relative to a repo checkout ("../../.kit/kit"); in a standalone bundle the kit sits at
# "$here/.kit/kit". Relink it so the folder builds wherever it was unpacked.
[ -f "$PLUGIN_DIR/tools/relink_kit.py" ] || die "missing tools/relink_kit.py in the bundle"
kit_rel="$(cd "$PLUGIN_DIR" && python3 -c 'import os,sys;print(os.path.relpath(sys.argv[1],sys.argv[2]))' "$KIT_DIR" "$PLUGIN_DIR")"
python3 "$PLUGIN_DIR/tools/relink_kit.py" "$PLUGIN_DIR/build.zig.zon" "$kit_rel" || die "could not relink the kit"
say "kit linked at $kit_rel"

say "building (zig build test, then ReleaseFast)"
"$ZIG" build >/dev/null || die "zig build test failed"
"$ZIG" build -Doptimize=ReleaseFast >/dev/null || die "release build failed"
dylib="$PLUGIN_DIR/zig-out/lib/libhy_mt2_sherry.dylib"
[ -f "$dylib" ] || die "no dylib at $dylib"
say "built $(du -h "$dylib" | cut -f1) dylib"

# ── conformance ──
say "running the conformance suite"
"$MLX_SERVE" plugin check "$dylib" 2>&1 | tail -3 || die "conformance failed"

if [ "${1:-}" = "--check-only" ]; then
  say "check-only: not installing"
  exit 0
fi

# ── install ──
say "installing into ~/.mlx-serve/plugins"
"$MLX_SERVE" plugin install "$dylib"

plugins_json="$HOME/.mlx-serve/plugins.json"
if [ ! -f "$plugins_json" ]; then
  printf '{\n  "disabled" : [\n\n  ],\n  "enabled" : true\n}\n' > "$plugins_json"
  say "wrote $plugins_json with plugins enabled"
elif ! grep -q '"enabled"[[:space:]]*:[[:space:]]*true' "$plugins_json"; then
  say "NOTE: plugins are disabled in $plugins_json — turn them on in the app (Settings > Server)"
fi

say "done. Restart mlx-serve, then check the log for:"
say "  [plugin] hy_mt2_sherry serves hunyuan_v1_dense"
say ""
say "If you do not have the model yet:"
say "  $MLX_SERVE pull Sube126/Hy-MT2-1.8B-1.25Bit-MLX"
say "  $MLX_SERVE --serve --model ~/.mlx-serve/models/Sube126/Hy-MT2-1.8B-1.25Bit-MLX"
