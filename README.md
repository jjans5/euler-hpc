# euler-hpc

A Claude Code plugin for working with coding agents on [Euler](https://docs.hpc.ethz.ch/), ETH Zurich's HPC
cluster. At session start on Euler it tells the agent which node it is on, what its allocation holds, and the
cluster rules that apply to every task; when work needs Slurm, its skill writes, submits and monitors the jobs.

| Part | What it does |
| --- | --- |
| `hooks/` | On Euler only, at session start: the node and allocation, plus always-on rules (login vs compute nodes, inline vs Slurm, modules, storage, snapshots). |
| `skills/euler-hpc/` | Slurm mechanics: job scripts, GPU jobs, job arrays, interactive allocations, monitoring, a failure table, and an sbatch template. Loaded on demand. |

Not affiliated with ETH Zurich; the [Euler docs](https://docs.hpc.ethz.ch/) are the reference.

## Use

Run Claude on Euler. One setup that works well: open an
[euler-tunnel](https://docs.hpc.ethz.ch/connections/euler-tunnel/) onto a compute node, start `tmux` there, and
run one Claude session per tmux window. Each session then starts inside an allocation, runs work inline while it
fits, and goes through Slurm when it doesn't. Ask in plain words: "run this on a GPU", "run this for every
sample", "hold a node for an hour", "why did my job fail?".

Settings, saved with `/plugin configure euler-hpc@quadbio` (the in-session `/plugin install` asks for them; a
shell install doesn't). Until saved, the agent asks.

| Setting | Default | Meaning |
| --- | --- | --- |
| `gpu_model` | `rtx_4090` | GPU model for GPU jobs; one your shareholder group can use. Blank: the agent asks. |
| `gpu_fallback` | `rtx_3090` | Model to try when the default queues too long. Blank: the agent asks. |

Slurm charges your default share. If you belong to several, set `SBATCH_ACCOUNT`, `SALLOC_ACCOUNT` and
`SLURM_ACCOUNT` in your shell profile. Personal conventions (where your projects live, cache locations, how you
run sweeps) go in your own `~/.claude/CLAUDE.md`.

## Install

Once, on Euler (all nodes share your home), from the
[quadbio marketplace](https://github.com/quadbio/claude-plugins); then save the settings above.

## Develop

```bash
claude plugin validate .
claude --plugin-dir .            # try the hook and skill from this checkout
pre-commit run --all-files
sh tests/test_session_start.sh   # on Euler
```

## Release

Bump `version` in `.claude-plugin/plugin.json`, tag `vX.Y.Z`, then bump the `ref` in
[quadbio/claude-plugins](https://github.com/quadbio/claude-plugins).

## License

MIT
