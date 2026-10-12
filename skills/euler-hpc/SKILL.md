---
name: euler-hpc
description: >-
  Write, submit, and monitor Slurm jobs on ETH Zurich's Euler cluster — sbatch scripts, job arrays, GPU jobs,
  interactive allocations, and the submit → squeue/sacct → logs loop. Use once work is going through Slurm;
  whether to run inline instead is decided before this skill. Trigger on "run this on the cluster", "submit a
  job", "sbatch this", "run on a GPU", "run this for every sample", "queue this on Euler", "hold a node", "is my
  job done?", "why did my job fail?". Cluster basics (which node, modules, storage, internet) come from this
  plugin's session-start context, not from this skill.
---

# Euler Slurm jobs

Three shapes: one **batch job**, a **job array** for many near-identical items, or an **interactive allocation**
to iterate on a node. Each has a section below. Cluster basics are in the session-start context; if it is
missing, read `${CLAUDE_PLUGIN_ROOT}/hooks/session_context.md`.

## Writing the job script

Start from `assets/euler_job.sh`. Euler-specific Slurm rules:

- **No `--partition`.** Slurm auto-selects it from your `--time` / `--gpus` / `--gres`.
- **`--time`** defaults to **1 h** if unset, and it *also selects the time-windowed partition* — so right-size
  it. Over-asking pushes you to a longer-queue partition (more wait); multi-day is allowed but the max is
  account-dependent.
- **Memory: `--mem-per-cpu` only.** Euler rejects `--mem`.
- **Threads:** one multithreaded process = `--ntasks=1 --cpus-per-task=N`. Slurm does **not** export
  `OMP_NUM_THREADS`, so set `export OMP_NUM_THREADS=${SLURM_CPUS_PER_TASK:-1}` or OpenMP/MKL/numba grab every
  visible core and oversubscribe.
- **Logs:** if the project says where batch logs go, use that. Otherwise `--output=logs/%x-%j.out`, and create
  `logs/` **at submit time** (`mkdir -p logs && sbatch …`). If the `--output` directory is missing the job **fails
  to launch and requeues in a loop** (no log, confusing PENDING/FAILED flapping) — `#SBATCH` lines are parsed
  before the script body, so a `mkdir` inside the script can't save it. The path resolves against the **submit
  directory**, not the script, so pass it absolutely (`sbatch --output="$LOGDIR/%x-%j.out" …`) whenever you
  submit from more than one place, or from a directory that may be deleted.
- **Paths:** the job starts in the submit directory. Pass anything that differs per machine or checkout at submit
  (`sbatch --export=ALL,MAIN="$main" job.sh`, or as script arguments) instead of hardcoding it in the script;
  some repos' guards refuse absolute paths in scripts.
- **Shared storage only.** The job runs on another node, so its working directory, inputs and log directory must
  be on home, project, work or scratch storage — never under `$TMPDIR` or `/tmp`, which are node-local (an
  agent's own scratch directory often is) — and must still exist when the job runs: don't remove a git worktree
  while jobs submitted from it are queued or running.
- **Env runner:** run work the way the project runs its scripts (`pixi run`, `uv run`, or what its `AGENTS.md`
  or workflow skill says; from a git worktree that may be `pixi run --manifest-path "$MAIN/pixi.toml"`). `sbatch`
  hands the job your submit environment, `PATH` included, but the job shell doesn't source `~/.bashrc`. If the
  manager isn't on `PATH` where you submit, or you pass `--export=NONE`, use its absolute path (`command -v pixi`).
- **In-job internet:** add `module load eth_proxy` only if the job downloads or talks to an online service.
- **Heavy many-small-file I/O:** stage to node-local **`$TMPDIR`** (request size with `--tmp=<size>`), compute
  there, copy results back — don't hammer shared storage.

Minimal CPU job:

```bash
#!/bin/bash
#SBATCH --job-name=myjob
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem-per-cpu=4g
#SBATCH --time=04:00:00
#SBATCH --output=logs/%x-%j.out
set -euo pipefail
export OMP_NUM_THREADS=${SLURM_CPUS_PER_TASK:-1}
pixi run python scripts/run_me.py     # runs in the submit directory
```

## GPU jobs

- **Request a specific GPU model**, not a bare `--gpus=1`: queues differ by model, and which models you can get
  depends on your shareholder group. From the user's plugin settings: default model "${user_config.gpu_model}",
  fallback "${user_config.gpu_fallback}". If one is empty or an unfilled placeholder, or the work needs more VRAM
  than it has, ask the user; they can save defaults with `/plugin configure euler-hpc@quadbio`.

  ```bash
  #SBATCH --gpus=<model>:1
  #SBATCH --gres=gpumem:24g      # VRAM floor — ALWAYS give a unit
  ```

- **`--gres=gpumem` units are mandatory.** `24g`/`24G` = 24 GiB. A **bare number is bytes** (`gpumem:24000` ≈
  24 KB → effectively no floor, and you silently land on a small card).
- **Models / VRAM** (docs: https://docs.hpc.ethz.ch/hardware/gpu_nodes/): `rtx_2080` 11g · `rtx_3090` /
  `rtx_4090` / `rtx_6000` / `nvidia_titan_rtx` 24g · `a100` 40g · `a100_80gb` 80g · `pro_6000` 96g. Slurm routes
  to the partition that has the model you asked for.
- **Which queue is shorter:** `sbatch --test-only job.sh` estimates the start time without submitting; compare
  the default and fallback model.
- **Account:** omit `--account`; Slurm uses your default share. If `my_share_info` lists several, ask the user
  which (they can set it once with `SBATCH_ACCOUNT`, `SALLOC_ACCOUNT` and `SLURM_ACCOUNT`).
- **Etiquette:** right-size model / `gpumem` / `--time`; don't hold an interactive GPU idle; `sbatch` long runs
  instead of sitting in an `srun --pty` GPU shell.

## Submit & monitor

```bash
mkdir -p logs
JOBID=$(sbatch --parsable job.sh)     # --parsable → just the numeric id, easy to capture
echo "submitted $JOBID"
```

- **Name jobs for this session**, e.g. after its task or worktree (`-J <task>-train`): other sessions share your
  user, and duplicate checks and lookups go by name.
- **Avoid duplicates:** before submitting, `squeue --me --name=<jobname>` — if one is already `PD`/`R`, don't
  resubmit.
- **Only cancel jobs you submitted.** Never `scancel --me`, and never the job this session runs in
  (`$SLURM_JOB_ID`): other jobs under your user may be a live session or a long run, and cancelling one is
  unrecoverable.
- **Poll, never block.** Do **not** use `tail -f` or `watch` — they hang a tool call until timeout. Take
  snapshots instead:

  ```bash
  squeue --me                       # or `myjobs` (Euler's readable squeue)
  sacct -j "$JOBID" --format=JobID,State,Elapsed,MaxRSS,ReqMem,ExitCode
  sstat -j "$JOBID"                 # live usage of a RUNNING job
  tail -n 40 logs/<jobname>-"$JOBID".out
  ```

  Cadence: ~30–60 s for short jobs, a few minutes for long ones. Stop when `sacct` `State` leaves
  `PENDING`/`RUNNING`. Cancel with `scancel "$JOBID"`.

## When a job fails — symptom → cause → fix

Read the **whole** log and the `sacct` row before concluding (a job leaving the queue is not the same as
success). `MaxRSS` is in KB unless suffixed.

| Symptom | Cause | Fix |
| --- | --- | --- |
| `FAILED`, no `.out`, flaps to `PENDING` | `logs/` dir missing at launch | `mkdir -p logs` before `sbatch` |
| `pixi: command not found` / `uv: …` | not on `PATH` at submit, or `--export=NONE` | absolute path to `pixi`/`uv` |
| `No such file`, or outputs in the wrong place | job ran in an unexpected directory, or it was removed | submit from the right directory; pass paths at submit |
| `OUT_OF_MEMORY`, `MaxRSS` ≈ `ReqMem` | system RAM | raise `--mem-per-cpu` |
| `CUDA out of memory` in log | GPU VRAM | raise `--gres=gpumem` (or smaller batch / bigger card) |
| `TIMEOUT` | walltime too low | raise `--time` |
| network hang/timeout on download | no `eth_proxy` | `module load eth_proxy` |
| GPU job never schedules | model/VRAM your share can't provide | another model (`sbatch --test-only`); check `my_share_info` |

## Job arrays (parallel, one task per item)

For embarrassingly-parallel work — one task per sample / week / parameter — a Slurm **array** runs N
near-identical tasks from a single script, each with a distinct `$SLURM_ARRAY_TASK_ID`. This is the
no-dependency, built-in way; for complex multi-parameter sweeps, if the project already has a sweep launcher
(e.g. Hydra's submitit launcher), offer it rather than assuming.

```bash
#SBATCH --array=0-9              # 10 tasks (indices 0..9). Also a list "0,3,5" or step "0-18:2"
#SBATCH --array=0-99%10          # throttle: at most 10 tasks run at once
#SBATCH --output=logs/%x-%A_%a.out   # %A=array job id, %a=task index — NOT %j (which would collide)
```

Map the index to the work item inside the script:

```bash
SAMPLES=(week2 week3 week4 week6)
S="${SAMPLES[$SLURM_ARRAY_TASK_ID]}"
pixi run python scripts/process.py --sample "$S"
# or pick the Nth line of a manifest:
# LINE=$(sed -n "$((SLURM_ARRAY_TASK_ID + 1))p" inputs.txt)
```

All tasks share `$SLURM_ARRAY_JOB_ID`. The `%N` throttle keeps tasks beyond the cap `PENDING` with reason
`JobArrayTaskLimit` — use it so you don't hammer the shared proxy or your fair-share. Monitor/cancel by the array
id: `squeue -j <A>`, `sacct -j <A>`; `scancel <A>` kills the whole array, `scancel <A>_<a>` one task. Use `%A_%a`
in `--output` so each task writes its own log (and still `mkdir -p logs` first).

## Interactive allocation

A person at a terminal outside a job gets a live shell on a compute node with:

```bash
# CPU
srun --ntasks=1 --cpus-per-task=4 --mem-per-cpu=4g --time=02:00:00 --pty bash
# GPU (pick a model as above; keep --time short; exit when done)
srun --gpus=<model>:1 --gres=gpumem:24g --cpus-per-task=4 --mem-per-cpu=8g \
     --time=01:00:00 --pty bash
```

Release it when you stop iterating — don't sit on a GPU.

An agent, driving over separate shell calls where `cd` and env don't persist, holds the node once and runs steps
into it:

```bash
salloc --no-shell --cpus-per-task=4 --mem-per-cpu=2g --time=01:00:00 -J <task>-explore
JID=$(squeue --me --name=<task>-explore -h -o "%i" | head -1)   # re-derive it every call
srun --jobid="$JID" --overlap -n1 bash -c '<command>'    # ~1–2 s, same node
scancel "$JID"
```

Two traps: `-n1` is required, else the step runs once per allocated core and output duplicates; and such a step
gets only **one** cpu's worth of memory (`--mem-per-cpu` × 1), so it can OOM while the allocation still has room.

## When this session runs inside a job

If `$SLURM_JOB_ID` is set (the session-start context says so), this session is itself a Slurm job:

- `sbatch` and `salloc` create new jobs as usual. A plain `srun` does **not**: it runs as a step of this session's
  job, on this node and from its resources. For a new allocation, use `salloc` or `sbatch`.
- `srun` takes this job's `SLURM_*` variables (`SLURM_CPUS_PER_TASK`, `SLURM_MEM_PER_CPU`, …) as defaults, so a
  step into another allocation can ask for more than it holds and hang. Clear them for that call:

  ```bash
  env $(env | sed -n 's/^\(SLURM_[A-Z0-9_]*\)=.*/-u \1/p') srun --jobid="$JID" --overlap -n1 bash -c '<command>'
  ```

## Quick reference

- No `--partition`; `--mem-per-cpu` (never `--mem`); `--time` picks the partition (default 1 h).
- GPU: `--gpus=<model>:1` (default "${user_config.gpu_model}", fallback "${user_config.gpu_fallback}") +
  `--gres=gpumem:24g` (unit required); omit `--account`.
- `mkdir -p logs && JOBID=$(sbatch --parsable job.sh)`; monitor with `squeue`/`myjobs`/`sacct`/`sstat` — never
  `tail -f`. Cancel only your own jobs, never this session's.
- Job names carry the task (`-J <task>-…`); paths come in at submit, not hardcoded; run scripts the project's way.
- Parallel per-item work: `--array=0-N%K` + `$SLURM_ARRAY_TASK_ID` + `--output=…%A_%a.out` (or the project's
  sweep launcher).
- Inside a job: plain `srun` is a step of this job; new allocations via `salloc`/`sbatch`; clear `SLURM_*` for
  `srun --jobid`.
- Template: `assets/euler_job.sh`.
