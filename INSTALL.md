# INSTALL.md — runbook for an AI agent

You are installing the **hy_mt2_sherry** plugin into **mlx-serve** on this Mac, then proving it serves Hy-MT2-1.8B
1.25-bit translation packs.

This file is written for an agent, not a human. Follow it in order. Every step has a **Check**; do not continue past a
failed Check. Report facts you observed, never what you expect.

**Rules**

- Run commands one at a time and read their output before the next.
- Never claim success without the three checks in Step 5.
- If a step fails and this file has no fix for it, stop and report the exact command, exit code, and output.
- Do not modify anything outside: this repo, `~/.mlx-serve/`, and the model directory.
- Do not run two mlx-serve servers that each load this model at once.

---

## Step 0 — Environment gate

```bash
uname -s; uname -m
```

**Check:** output is exactly `Darwin` and `arm64`.

- If `Linux`/`Windows`: stop. This plugin's kernels are Apple Metal; there is no build for other platforms.
- If `x86_64`: stop. Intel Macs are not supported (mlx-serve needs Apple Silicon).

```bash
xcode-select -p
```

**Check:** prints a path such as `/Library/Developer/CommandLineTools`.

- If it errors with "unable to find utility": run `xcode-select --install`, wait for the dialog to finish, and repeat.

```bash
command -v mlx-serve || ls -l /Applications/MLX-Serve.app/Contents/MacOS/mlx-serve
```

**Check:** one of them exists. Then pin the path for this session:

```bash
if command -v mlx-serve >/dev/null 2>&1; then
  export MLX_SERVE="$(command -v mlx-serve)"
else
  export MLX_SERVE="/Applications/MLX-Serve.app/Contents/MacOS/mlx-serve"
fi
echo "$MLX_SERVE"
```

> **Every command block below runs in its own shell.** If your tool does not keep variables between calls, prepend
> this to each block that uses `$MLX_SERVE`:
> `MLX_SERVE="$(command -v mlx-serve || echo /Applications/MLX-Serve.app/Contents/MacOS/mlx-serve)"`
> The blocks below are written as one session (variables persist). Mind this if yours do not.

```bash
"$MLX_SERVE" --version 2>&1 | grep -E '^mlx-serve [0-9]'
```

**Check:** the version is **26.11.1 or newer** (e.g. `mlx-serve 26.11.2 (fast)`).

- If it is older: stop and report that mlx-serve must be updated first (the plugin kit ships from 26.11.1).

```bash
"$MLX_SERVE" plugin 2>&1 | grep -c "plugin install"
```

**Check:** prints `1` or more. (`mlx-serve plugin` with no subcommand prints usage and exits 1 — that is normal; read
the output, not the exit status.)

- If it prints `0`: this build has no plugin support. Stop and report the exact version output.

---

## Step 1 — Get the source

If you are already inside a checkout containing `plugin/plugin.zig`:

```bash
ls plugin/plugin.zig plugin/install.sh
```

**Check:** both paths exist. Skip the clone.

Otherwise, prefer the release tarball (no git needed):

```bash
cd ~
# `latest` always resolves to the current release; the asset name matches the tag it points at.
TAG="$(curl -fsSL https://api.github.com/repos/mobailabs/hy-mt2-sherry-mlx-serve/releases/latest \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])')"
echo "release $TAG"
curl -fsSL -o hy-mt2.tar.gz \
  "https://github.com/mobailabs/hy-mt2-sherry-mlx-serve/releases/download/$TAG/hy-mt2-sherry-mlx-serve-$TAG.tar.gz"
tar -xzf hy-mt2.tar.gz
cd hy-mt2-sherry-mlx-serve
```

**Check:** `ls plugin/plugin.zig plugin/install.sh` succeeds.

- If `curl` fails with 404 or the release lookup fails: fall back to git:
  `git clone https://github.com/mobailabs/hy-mt2-sherry-mlx-serve && cd hy-mt2-sherry-mlx-serve`.
- Optional integrity check: `shasum -a 256 hy-mt2.tar.gz` should equal the digest on the release page.

---

## Step 2 — Build and verify, without installing

```bash
./plugin/install.sh --check-only
```

This does, in order: finds mlx-serve, downloads Zig 0.17.0 into `.zig-toolchain/`, downloads the plugin kit for **your
server's own release**, compares the kit's MLX pin with the server's, runs the plugin's unit tests, builds
`ReleaseFast`, and runs `mlx-serve plugin check` on the built dylib.

Takes 1–5 minutes the first time (downloads). It may print `Zig download failed (attempt N), retrying` or
`downloading kit ... (attempt N)` — that is expected; both retry five times.

**Check — all three lines must appear:**

```
[hy_mt2] pin matches the server: mlx=<hash> ... target=26.2
[hy_mt2] built <n>K dylib
hy_mt2_sherry (model) passes the conformance suite
```

### If it fails

| Output | Meaning | Action |
|---|---|---|
| `could not download Zig` | ziglang.org unreachable | Retry once. Still failing: install Zig **0.17.0** by hand, put `zig` on `PATH`, re-run. |
| `could not download the plugin kit` | GitHub 504s | Retry. Still failing: see "Kit fallback" below. |
| `WARNING: kit pin differs from this server's` | kit ≠ server | **Do not install.** See "Kit fallback" and get the kit for this server's release. |
| `has no 'plugin' command` | server too old | Stop; report the version. |
| `error: ... plugin.zig` (compile) | toolchain mismatch | `rm -rf .kit .zig-toolchain plugin/.zig-cache plugin/zig-out` and re-run once. |
| `does not pass the conformance suite` | real defect | Stop; report the whole conformance output. |

**Kit fallback** — build a kit from the server's source once:

```bash
cd ~
git clone --recurse-submodules https://github.com/ddalcu/mlx-serve
cd mlx-serve
xcodebuild -downloadComponent MetalToolchain     # only if it says the Metal toolchain is missing
zig build kit
ls zig-out/kit/                              # note the mlx-serve-plugin-kit-<version> folder
```

Then re-run the installer pointing at it:

```bash
cd ~/hy-mt2-sherry-mlx-serve
MLX_SERVE_KIT="$HOME/mlx-serve/zig-out/kit/mlx-serve-plugin-kit-<version>" ./plugin/install.sh --check-only
```

---

## Step 3 — Install

```bash
./plugin/install.sh
```

**Check:** it ends with

```
[hy_mt2] installing into ~/.mlx-serve/plugins
installed hy_mt2_sherry 0.1.0 (model) into ~/.mlx-serve/plugins
```

Then confirm plugins are enabled:

```bash
cat ~/.mlx-serve/plugins.json
```

**Check:** contains `"enabled" : true`.

- If the file is missing the installer creates it. If it says `false`, set it to `true`, or tell the user to switch it
  on in the app: **Settings ▸ Server ▸ Plugins**.

Plugins load only at server start. If an mlx-serve server is already running, restart it:

```bash
pgrep -fl "mlx-serve" | head
```

---

## Step 4 — Get the model

```bash
ls ~/.mlx-serve/models/Sube126/Hy-MT2-1.8B-1.25Bit-MLX/model.safetensors
```

**Check:** the file exists (~454 MB).

- If missing, pull it (~440 MB download):

  ```bash
  MLX_SERVE="$(command -v mlx-serve || echo /Applications/MLX-Serve.app/Contents/MacOS/mlx-serve)"
  "$MLX_SERVE" pull Sube126/Hy-MT2-1.8B-1.25Bit-MLX
  ```

  **Check:** ends with `success: Sube126/Hy-MT2-1.8B-1.25Bit-MLX ready`.

---

## Step 5 — Prove it works (three checks)

Pick a free port and start the server in the background:

```bash
# self-contained: rebuilds the two variables in case this block gets a fresh shell
MLX_SERVE="$(command -v mlx-serve || echo /Applications/MLX-Serve.app/Contents/MacOS/mlx-serve)"
PORT=18888
"$MLX_SERVE" --serve \
  --model ~/.mlx-serve/models/Sube126/Hy-MT2-1.8B-1.25Bit-MLX \
  --port "$PORT" --host 127.0.0.1 > /tmp/hy_mt2_serve.log 2>&1 &
echo $! > /tmp/hy_mt2_serve.pid
sleep 1
cat /tmp/hy_mt2_serve.pid >/dev/null && kill -0 "$(cat /tmp/hy_mt2_serve.pid)" 2>/dev/null \
  && echo "started pid $(cat /tmp/hy_mt2_serve.pid)" \
  || { echo "FAILED to start; log:"; tail -20 /tmp/hy_mt2_serve.log; }

for i in $(seq 1 60); do
  curl -sf "http://127.0.0.1:$PORT/v1/models" >/dev/null 2>&1 && break
  sleep 2
done
curl -s "http://127.0.0.1:$PORT/v1/models" >/dev/null && echo "server up" || echo "server NOT up"
```

### Check 1 — the plugin is the one serving the pack

```bash
grep -E "\[plugin\] hy_mt2_sherry serves|Model: unknown|error: " /tmp/hy_mt2_serve.log | head -5
```

**Pass:** a line `[plugin] hy_mt2_sherry serves hunyuan_v1_dense (32 layers)`.

**Fail:** `Model: unknown (...0-bit affine quant ...)` or `error: LoadFailed`. The plugin did not load — go to
"Server refuses the plugin" below.

### Check 2 — it translates correctly

```bash
curl -s "http://127.0.0.1:$PORT/v1/chat/completions" \
  -H 'content-type: application/json' \
  -d '{"model":"Sube126/Hy-MT2-1.8B-1.25Bit-MLX",
       "messages":[{"role":"user","content":"Translate into English, output only the translation:\n\n今天天气真好。"}],
       "max_tokens":16,"temperature":0}' \
  > /tmp/hy_mt2_resp.json
python3 -c "import json;d=json.load(open('/tmp/hy_mt2_resp.json'));print(repr(d['choices'][0]['message']['content']))"
```

**Pass:** a fluent English sentence containing `weather` and `nice`/`good` — `'The weather is really nice today.'`.

**Fail:** HTTP error, empty string, mojibake, or repeated tokens. Report `/tmp/hy_mt2_resp.json` and the log tail.

### Check 3 — it is running on the GPU, not a fallback

```bash
python3 -c "import json;t=json.load(open('/tmp/hy_mt2_resp.json'))['timings'];print('decode', round(t['predicted_per_second'],1), 'tok/s')"
```

**Pass:** above **50** tok/s (≈300 on an M5 Max, ≈100 on an M1). Single digits mean the wrong path or CPU fallback —
report it, do not call it a success.

### Shut down

```bash
kill "$(cat /tmp/hy_mt2_serve.pid)" 2>/dev/null
lsof -ti tcp:$PORT | xargs -r kill -9 2>/dev/null
```

### Server refuses the plugin

Typical message: `plugin was built against another MLX: rebuild it with this release's kit`. Negotiation is an
**exact string match**, so compare both pins:

```bash
strings ~/.mlx-serve/plugins/hy_mt2_sherry.dylib | grep -E '^mlx=.*target='
MLX_SERVE="$(command -v mlx-serve || echo /Applications/MLX-Serve.app/Contents/MacOS/mlx-serve)"
strings "$MLX_SERVE" | grep -E '^mlx=.*target='
```

- **Different** → rebuild against the server's kit:
  `MLX_SERVE_KIT=<kit for this server's release> ./plugin/install.sh`, then restart the server.
- **Identical** → stale artifacts on disk:

  ```bash
  rm -rf .kit .zig-toolchain plugin/.zig-cache plugin/zig-out
  ./plugin/install.sh
  ```

  then restart the server.

Other refusals to report as-is: `no 'plugin' command`, `hash` mismatch (reinstall with `./plugin/install.sh`),
`plugins are disabled` (Step 3).

**A dylib is never unloaded inside a running server.** After any install, kill and restart it.

---

## Step 6 — Report

Reply with exactly these, using values you observed:

```
Host:        <uname -m>, macOS <sw_vers -productVersion>
mlx-serve:   <version line>
kit pin:     <mlx=... target=...>
server pin:  <mlx=... target=...>   (equal to kit? yes/no)
Build:       <tests passed? conformance passed?>
Serving:     <the [plugin] line, verbatim>
Translation: <the sentence from Check 2>
Decode:      <n> tok/s
Workarounds: <none | what and why>
Verdict:     PASS | FAIL (<which check>)
```

If anything failed, set `Verdict: FAIL`, name the check, and include the failing command, its exit code, and the last
20 lines of `/tmp/hy_mt2_serve.log`. Do not report `PASS` unless all three checks passed.

---

## Appendix — what you are installing

`hy_mt2_sherry` teaches mlx-serve the Hy-MT2-1.8B **1.25-bit** packs (`Sube126/Hy-MT2-1.8B-1.25Bit-MLX` and
`kuotient`'s copy). They are `hunyuan_v1_dense` with llama.cpp **STQ1_0** projections (`qs`/`sign`/`scales`,
1.3125 bits per weight) and a 6-bit affine embedding. mlx-serve does not read that layout on its own: with
`--no-plugins` the same pack fails with `error: LoadFailed`.

The plugin ports the pack's model code and its Metal kernels (decode GEMV, multi-slot batch GEMV up to 64 rows per
slot, dequant + GEMM above that). The host keeps the tokenizer, chat template, sampling, KV cache, prefix cache,
batching and HTTP APIs.

Things you may be asked about, and should not try to "fix":

- **Context is 32768 by default**, not the pack's 262144: KV is 64 KiB/token, so the full window would bill 16 GiB.
  Raise it with the server's `--ctx-size` (up to 262144). mlx-serve's per-model `ctx_size` setting does not reach an
  outside plugin — the server flag is the only lever.
- **Multi-Mac layer split** is refused by name.
- **Every mlx-serve upgrade requires re-running `./plugin/install.sh`**: the dylib embeds the MLX pin.
