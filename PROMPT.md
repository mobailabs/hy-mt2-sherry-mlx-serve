# Task: install and verify the hy_mt2_sherry plugin for mlx-serve

You are an AI agent working on a **Mac with Apple Silicon**. Your job is to install the `hy_mt2_sherry` plugin into
`mlx-serve`, pull the model it serves, and prove it works. Work step by step; after each step check the stated
success condition before moving on.

Do not skip verification. Do not report success without the checks in step 5.

---

## 0. Preconditions to check first

Run these and confirm the output:

```bash
uname -s && uname -m
```

- Must print `Darwin` and `arm64`. If not, **stop** and report: the plugin's kernels are Apple Metal, it cannot work
  on Linux, Windows or an Intel Mac.

```bash
mlx-serve --version || /Applications/MLX-Serve.app/Contents/MacOS/mlx-serve --version
```

- You need **26.11.1 or newer** (the release that ships the plugin kit). The output line looks like
  `mlx-serve 26.11.2 (fast)`.
- Export whichever path works for the rest of the session:

  ```bash
  export MLX_SERVE="$(command -v mlx-serve || echo /Applications/MLX-Serve.app/Contents/MacOS/mlx-serve)"
  ```

```bash
xcode-select -p
```

- Must print a path. If it errors: `xcode-select --install` and wait for it to finish.

---

## 1. Get the source

If the repo is already present, work in it. Otherwise:

```bash
git clone https://github.com/mobailabs/hy-mt2-sherry-mlx-serve
cd hy-mt2-sherry-mlx-serve
```

Success condition: `plugin/plugin.zig` and `plugin/install.sh` exist.

---

## 2. Build and verify without installing

```bash
./plugin/install.sh --check-only
```

This downloads the pinned Zig (0.17.0) and the plugin kit **for your mlx-serve's own release**, checks that the kit's
MLX pin equals your server's, runs the plugin's tests, and runs `mlx-serve plugin check`.

Success condition: the last lines are

```
[hy_mt2] running the conformance suite
...
hy_mt2_sherry (model) passes the conformance suite
[hy_mt2] check-only: not installing
```

### If it fails

**`could not download the plugin kit` / repeated HTTP 504.** GitHub serves these assets unreliably. Retry
`./plugin/install.sh --check-only`, or supply a kit you build once:

```bash
git clone --recurse-submodules https://github.com/ddalcu/mlx-serve
cd mlx-serve
xcodebuild -downloadComponent MetalToolchain     # once, if the Metal toolchain is missing
zig build kit
cd -
MLX_SERVE_KIT="$(pwd)/mlx-serve/zig-out/kit/mlx-serve-plugin-kit-<version>" ./plugin/install.sh --check-only
```

**`WARNING: kit pin differs from this server's`.** The build will succeed and the server will refuse the plugin at
load. Re-run with the kit of the server's release (the loop already tries that first, so this usually means the
download fell back to the older `KIT_VERSION`). Fix it before installing:

```bash
MLX_SERVE_KIT=/path/to/mlx-serve-plugin-kit-<your server version> ./plugin/install.sh
```

**`this mlx-serve (...) has no 'plugin' command`.** The server is older than 26.11.1. Stop and report: the app must
be updated first.

**Zig download fails.** Install Zig 0.17.0 manually and put it on `PATH`, then re-run.

---

## 3. Install

```bash
./plugin/install.sh
```

Success condition: it ends with `[plugin] hy_mt2_sherry serves hunyuan_v1_dense` in the "done" note, and prints
where it installed.

If it says plugins are disabled, enable them: either in the app (Settings > Server > Plugins) or by editing
`~/.mlx-serve/plugins.json` to contain `"enabled": true`.

---

## 4. Pull the model (skip if already present)

```bash
ls ~/.mlx-serve/models/Sube126/Hy-MT2-1.8B-1.25Bit-MLX/config.json
```

If missing:

```bash
"$MLX_SERVE" pull Sube126/Hy-MT2-1.8B-1.25Bit-MLX
```

Success condition: `success: Sube126/Hy-MT2-1.8B-1.25Bit-MLX ready` and the directory holds `model.safetensors`
(~454 MB), `config.json`, `tokenizer.json`.

---

## 5. Verify it actually serves

Start the server in the background and capture the log:

```bash
"$MLX_SERVE" --serve \
  --model ~/.mlx-serve/models/Sube126/Hy-MT2-1.8B-1.25Bit-MLX \
  --port 18888 --host 127.0.0.1 > /tmp/hy_mt2_serve.log 2>&1 &
sleep 20
grep -E "plugin\] |error|failed" /tmp/hy_mt2_serve.log
```

**Check 1 — the plugin is the one serving the pack.** The log must contain:

```
[plugin] hy_mt2_sherry serves hunyuan_v1_dense (32 layers)
```

If instead you see `Model: unknown ... 0-bit affine quant` or `error: LoadFailed`, the plugin did not load. Read
`~/.mlx-serve/logs/mlx-serve-18888.log` and go to "If the server refuses the plugin" below.

**Check 2 — it translates.** Run:

```bash
curl -s http://127.0.0.1:18888/v1/chat/completions \
  -H 'content-type: application/json' \
  -d '{"model":"Sube126/Hy-MT2-1.8B-1.25Bit-MLX",
       "messages":[{"role":"user","content":"Translate into English, output only the translation:\n\n今天天气真好。"}],
       "max_tokens":16,"temperature":0}'
```

Expected content: `The weather is really nice today.` — a fluent English sentence. Garbage, empty output, repeated
tokens, or an HTTP error all mean failure; capture the full JSON and the log tail.

**Check 3 — it is fast enough to be real.** In the same JSON, `timings.predicted_per_second` should be **above 50**
on any Apple Silicon Mac (it is ~300 tok/s on an M5 Max). A single-digit number suggests the wrong code path or CPU
fallback.

Stop the server:

```bash
kill %1 2>/dev/null; lsof -ti tcp:18888 | xargs -r kill -9
```

### If the server refuses the plugin

The message is usually `plugin was built against another MLX: rebuild it with this release's kit`. Negotiation is an
**exact string match**, so compare the two pins directly:

```bash
strings ~/.mlx-serve/plugins/hy_mt2_sherry.dylib | grep -E '^mlx=.*target='
strings "$MLX_SERVE" | grep -E '^mlx=.*target='
```

- **They differ** → the kit does not match this server. Find which release `$MLX_SERVE` is and open that release on
  GitHub, download `mlx-serve-plugin-kit-<version>.tar.gz`, then
  `MLX_SERVE_KIT=<extracted kit> ./plugin/install.sh`.
- **They are identical** → a stale build is on disk. Clean and re-run:

  ```bash
  rm -rf .kit .zig-toolchain plugin/.zig-cache plugin/zig-out
  ./plugin/install.sh
  ```

A dylib is never unloaded inside a running server: **restart** the server after every install.

---

## 6. Report

Report concisely:

1. `uname -m`, the `mlx-serve` version, and both MLX pins (kit vs server).
2. Whether `--check-only` passed and how many tests ran.
3. The exact line from the log proving the plugin serves the pack.
4. The translated sentence from check 2 and `predicted_per_second` from check 3.
5. Anything you had to work around (kit download retries, `MLX_SERVE_KIT`, plugins disabled, …).

If any check failed, report what failed, the full error text, and the tail of the server log. Do not claim success.

---

## Reference: what this plugin is

`hy_mt2_sherry` teaches mlx-serve the Hy-MT2-1.8B **1.25-bit** packs (`Sube126/Hy-MT2-1.8B-1.25Bit-MLX`,
`kuotient/Hy-MT2-1.8B-1.25Bit-MLX`). They are `hunyuan_v1_dense` with llama.cpp **STQ1_0** projections
(`qs`/`sign`/`scales`, 1.3125 bits per weight) and a 6-bit affine embedding — a layout mlx-serve does not read on its
own (`--no-plugins` on this pack gives `error: LoadFailed`). The plugin ports the pack's model code and its Metal
kernels; the host keeps the tokenizer, chat template, sampling, KV cache, prefix cache, batching and HTTP APIs.

Limits worth knowing, not to fix:

- **Context defaults to 32768**, not the pack's 262144: KV is 64 KiB/token, so the full window would bill 16 GiB.
  Raise it with the server's `--ctx-size` (up to 262144). mlx-serve's per-model `ctx_size` setting does not reach an
  outside plugin; the server flag is the only lever.
- **Multi-Mac layer split** is refused by name.
- **Plugins must be rebuilt after every mlx-serve upgrade** — the dylib embeds the MLX pin.
