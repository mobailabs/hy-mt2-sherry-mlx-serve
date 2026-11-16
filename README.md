# hy-mt2-sherry-mlx-serve

An [mlx-serve](https://github.com/ddalcu/mlx-serve) model plugin for **Hy-MT2-1.8B 1.25-bit** translation packs.
mlx-serve does not ship this; upstream [CommunityServe/plugins#26](https://github.com/CommunityServe/plugins/pull/26)
is still open, so this repo is the distributable form.

Serves:

- `Sube126/Hy-MT2-1.8B-1.25Bit-MLX`
- `kuotient/Hy-MT2-1.8B-1.25Bit-MLX`

Both are `hunyuan_v1_dense` with llama.cpp **STQ1_0** projections (`qs` / `sign` / `scales`, 1.3125 bits per weight)
and a 6-bit affine embedding. The plugin ports the pack's model code and its Metal kernels; mlx-serve keeps the
tokenizer, chat template, sampling, KV cache, prefix cache, batching and HTTP APIs.

## Let an AI do it

> **Copy this to an AI** (Claude Code, Codex, OpenCode, Cursor, …) and it installs and verifies.
> Run it **on the Mac you are installing to**, not somewhere else.
>
> ```
> You are installing the hy_mt2_sherry plugin for mlx-serve on this Mac.
>
> Follow https://raw.githubusercontent.com/mobailabs/hy-mt2-sherry-mlx-serve/main/INSTALL.md
> exactly, step by step. If you cannot fetch that URL, use this fallback:
> https://github.com/mobailabs/hy-mt2-sherry-mlx-serve (clone it, then read INSTALL.md).
>
> Rules:
> - Do not skip the Checks. Do not report success unless all three checks in Step 5 pass.
> - Report exactly what you observed, in the format Step 6 specifies.
> - If a step fails and INSTALL.md has no fix for it, stop and report the exact command,
>   its output, and the exit code.
> ```

[`INSTALL.md`](INSTALL.md) is the runbook the agent follows: numbered steps, a **Check** after each, a failure table
mapping output to fix, three acceptance tests, and a fixed report format. [`PROMPT.md`](PROMPT.md) is the same job as
a prompt, for tools that prefer a task statement.

## Install manually

Apple Silicon macOS, mlx-serve **26.11.1 or newer**.

```bash
TAG="$(curl -fsSL https://api.github.com/repos/mobailabs/hy-mt2-sherry-mlx-serve/releases/latest \
       | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])')"
curl -fsSL -o hy-mt2.tar.gz \
  "https://github.com/mobailabs/hy-mt2-sherry-mlx-serve/releases/download/$TAG/hy-mt2-sherry-mlx-serve-$TAG.tar.gz"
tar -xzf hy-mt2.tar.gz && cd hy-mt2-sherry-mlx-serve
./plugin/install.sh
```

Or from git:

```bash
git clone https://github.com/mobailabs/hy-mt2-sherry-mlx-serve
cd hy-mt2-sherry-mlx-serve
./plugin/install.sh
```

The script finds mlx-serve, fetches the plugin kit **for that release**, downloads the pinned Zig, checks the MLX pin
matches, builds, runs the conformance suite, and installs. Build without installing: `--check-only`.

Then:

```bash
mlx-serve pull Sube126/Hy-MT2-1.8B-1.25Bit-MLX
mlx-serve --serve --model ~/.mlx-serve/models/Sube126/Hy-MT2-1.8B-1.25Bit-MLX
```

The log must show `[plugin] hy_mt2_sherry serves hunyuan_v1_dense (32 layers)`.

## Performance

Apple M5 Max, greedy, `--no-pld`, idle machine:

| Scenario | Decode | Prefill |
|---|---:|---:|
| 74-token prompt, single stream | 355 tok/s | 1.8–2.0k tok/s |
| 282-token prompt, single stream | 290–333 tok/s | 4.5–5.5k tok/s |
| 646-token prompt | — | 6.3–7.6k tok/s |
| 4 slots | 146–157 each, **586–623 aggregate** | — |

## Limits

- Context defaults to **32768** (KV is 64 KiB/token; the pack's 262144 window would bill 16 GiB). Raise it with
  `--ctx-size`; mlx-serve's per-model `ctx_size` setting does not reach an outside plugin.
- Multi-Mac layer split is refused by name.
- Rebuild after every mlx-serve upgrade: the dylib embeds the MLX pin.

## Layout

```
INSTALL.md             runbook for an AI agent: steps, checks, failure fixes, report format
PROMPT.md              the same job as a prompt
plugin/                the plugin package
  install.sh           the installer (local + kit download + pin check + build + conformance)
  plugin.zig           forward, the three Metal kernels, weight loading, the bill
  config.zig           claim, parse, the config refusals
  src/conformance_fixture.zig   a 2-layer pack with real STQ1_0 weights and a real 6-bit embedding
  INSTALL.md           manual steps and troubleshooting
```

## Provenance

The plugin's `gemv_src` / `dequant_src` are ports of the pack's `sherry_model.py`; the decoder follows mlx-lm's
`hunyuan_v1_dense.py` (Apple, MIT). See `plugin/NOTICE`. STQ1_0 follows llama.cpp PR #22836.

## License

MIT, except the vendored model code listed in `plugin/NOTICE` (Apache-2.0 from the model releases).
