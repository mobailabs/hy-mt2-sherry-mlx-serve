# hy_mt2_sherry — install on another Mac

`mlx-serve` does not ship this plugin. It is compiled from the source in this folder, so the folder carries
everything needed: no git, no PR, nothing to download from us.

Target: Apple Silicon macOS with **mlx-serve 26.11.1 or newer** (the release that has the plugin kit).

## Quick start

```bash
tar -xzf hy_mt2_sherry-plugin.tar.gz
cd hy_mt2_sherry
./install.sh
```

The script:

1. finds `mlx-serve` (PATH, or `/Applications/MLX-Serve.app/…/mlx-serve`; override with `MLX_SERVE=…`);
2. reads its version and fetches **that release's** plugin kit (retrying: GitHub returns 504 on these assets a lot);
3. downloads the pinned Zig 0.17.0 into `.zig-toolchain/`;
4. warns if the kit's MLX pin differs from the server's — that is the one thing that makes mlx-serve refuse a plugin;
5. builds (`zig build` runs the 17 tests), runs `mlx-serve plugin check`;
6. installs the dylib and turns plugins on in `~/.mlx-serve/plugins.json`.

To build and verify without installing: `./install.sh --check-only`.

## Then

```bash
mlx-serve pull Sube126/Hy-MT2-1.8B-1.25Bit-MLX
mlx-serve --serve --model ~/.mlx-serve/models/Sube126/Hy-MT2-1.8B-1.25Bit-MLX --ctx-size 32768
```

The log must show `[plugin] hy_mt2_sherry serves hunyuan_v1_dense (32 layers)`, and `/v1/models` shows
`"plugin": "hy_mt2_sherry"`.

```bash
curl http://localhost:11234/v1/chat/completions -H 'content-type: application/json' -d '{
  "model": "Sube126/Hy-MT2-1.8B-1.25Bit-MLX",
  "messages": [{"role":"user","content":"Translate into English, output only the translation:\n\n今天天气真好。"}],
  "temperature": 0
}'
```

## If the kit will not download

GitHub serves `mlx-serve-plugin-kit-<version>.tar.gz` with frequent 504s. Options:

```bash
# a kit you already staged elsewhere
MLX_SERVE_KIT=/path/to/mlx-serve-plugin-kit-26.11.2 ./install.sh

# or build one from the server's source
git clone --recurse-submodules https://github.com/ddalcu/mlx-serve
cd mlx-serve && xcodebuild -downloadComponent MetalToolchain && zig build kit
MLX_SERVE_KIT=$PWD/zig-out/kit/mlx-serve-plugin-kit-<version> ../install.sh
```

## If mlx-serve refuses the plugin at load

> `plugin was built against another MLX: rebuild it with this release's kit`

Compare the two pins — negotiation is an exact string match, not a version number:

```bash
strings ~/.mlx-serve/plugins/hy_mt2_sherry.dylib | grep -E '^mlx=.*target='
strings /Applications/MLX-Serve.app/Contents/MacOS/mlx-serve | grep -E '^mlx=.*target='
```

- **different** → the kit does not match this server. Re-run `./install.sh`; it fetches the server's own release.
- **identical** → a stale build is on disk: `rm -rf .kit .zig-toolchain plugins/hy_mt2_sherry/.zig-cache
  plugins/hy_mt2_sherry/zig-out` and re-run.

After every mlx-serve upgrade, run `./install.sh` again: the dylib embeds the MLX pin, and a dylib is never unloaded
inside a running server — restart it.

## Manual build

If you would rather drive it by hand:

```bash
cd plugins/hy_mt2_sherry
MLX_SERVE_KIT=/path/to/kit /path/to/.zig-toolchain/zig build            # tests
MLX_SERVE_KIT=/path/to/kit /path/to/.zig-toolchain/zig build -Doptimize=ReleaseFast
mlx-serve plugin check zig-out/lib/libhy_mt2_sherry.dylib
mlx-serve plugin install zig-out/lib/libhy_mt2_sherry.dylib
```

## What it does not support

- **Intel Macs** — the STQ kernels are Apple Metal, and mlx-serve needs Apple Silicon.
- **Other Hunyuan dense packs** — only packs carrying `sherry_embed_bits` (or `model_file: sherry_model.py`) are
  claimed.
- **The full 262144-token window by default** — KV is 64 KiB/token, so `context_cap` defaults to 32768. Raise it with
  the server's `--ctx-size` (up to the pack's window).
- **Multi-Mac layer split** — refused by name.
- **mlx-serve's per-model `ctx_size` setting** — it does not reach an outside plugin (`LoadCtx.settings_json` arrives
  empty); use `--ctx-size`.
