# euler-hpc

A Claude Code plugin for running coding agents efficiently on [Euler](https://docs.hpc.ethz.ch/), ETH Zurich's
HPC cluster. It holds everything specific to the cluster, so other plugins can stay cluster-agnostic: at session
start it tells the agent which node it is on, what its allocation holds, your own setup and the rules for every
session; its skill covers Slurm jobs, software and data, summarising the docs and pointing to their pages; and it
links each job to the Claude session that submitted it.

| Part | What it does |
| --- | --- |
| `hooks/` | On Euler only, at session start: node and allocation, your settings, always-on rules (nodes, inline vs Slurm, modules, storage, snapshots, cancelling). Tags the session's jobs and records the session. |
| `skills/euler-hpc/` | Slurm batch jobs, GPU jobs, arrays, interactive allocations, monitoring and failures; software, containers, moving data. An sbatch template. Loaded on demand. |
| `skills/jobs/`, `bin/euler-jobs` | `/euler-hpc:jobs`: your jobs grouped by the session that submitted them, with each session's directory, tmux window and whether it is still open. |

Not affiliated with ETH Zurich; the [Euler docs](https://docs.hpc.ethz.ch/) are the reference.

## Use

Run Claude on Euler. One setup that works well: open an
[euler-tunnel](https://docs.hpc.ethz.ch/connections/euler-tunnel/) onto a compute node, start `tmux` there, and
run one Claude session per tmux window. Each session then starts inside an allocation, runs work inline while it
fits, and goes through Slurm when it doesn't. Ask in plain words: "run this on a GPU", "run this for every
sample", "hold a node for an hour", "why did my job fail?".

`/euler-hpc:jobs` lists your jobs by session. It knows a job's session because the plugin tags everything a
session submits with `sbatch` or `salloc` (`--comment=claude:<session>`); jobs from elsewhere are listed apart.

Settings, saved with `/plugin configure euler-hpc@quadbio` (the in-session `/plugin install` asks for them; a
shell install doesn't). They hold what is specific to you on Euler, so your `CLAUDE.md` needn't.

| Setting | Default | Meaning |
| --- | --- | --- |
| `gpu_model` | `rtx_4090` | GPU model for GPU jobs; one your shareholder group can use. Blank: the agent asks. |
| `gpu_fallback` | `rtx_3090` | Model to try when the default queues too long. Blank: the agent asks. |
| `group` | | Your group's storage name, as in `/cluster/project/<group>`. |
| `work_root` | | Where your repositories and work live. |
| `notes` | | Other facts about your setup, separated by semicolons, e.g. where shared datasets live. |

Slurm charges your default share. If you belong to several, set `SBATCH_ACCOUNT`, `SALLOC_ACCOUNT` and
`SLURM_ACCOUNT` in your shell profile.

## Install

Once, on Euler (all nodes share your home), from the
[quadbio marketplace](https://github.com/quadbio/claude-plugins); then save the settings above.

## Develop

```bash
claude plugin validate .
claude --plugin-dir .            # try the hook and skill from this checkout
pre-commit run --all-files
sh tests/test_session_start.sh   # on Euler
sh tests/test_euler_jobs.sh
```

## Release

Bump `version` in `.claude-plugin/plugin.json`.
That is the release: the marketplace follows `main`, users update when the version changes, and the merge tags
`vX.Y.Z`.

## License

MIT
