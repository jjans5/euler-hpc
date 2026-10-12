This session runs on Euler, ETH Zurich's HPC cluster. Its docs, https://docs.hpc.ethz.ch/, are the authority on
cluster setup: read them rather than guess. Always:

1. Login nodes (`eu-login-*`) are for git, downloads and light work only, never computation. Compute nodes are
   firewalled: `module load eth_proxy` before anything that needs the internet.
2. Before heavy work, check whether this session's allocation (above) covers its cores, memory, GPU and walltime;
   measure rather than assume. If it fits, run inline. If not, or on a login node, go through Slurm, and load the
   `euler-hpc` skill before writing any `sbatch`, `srun` or `salloc`.
3. No software stack loads by default: `module load stack/<version>`, then packages; search with `module spider`.
   Take versions from the docs, never hardcode them.
4. Pick storage by what the data needs (table below). Keep work, data, environments and package caches out of home:
   uv, pixi, pip and Hugging Face default to `~/.cache`.
5. Before declaring anything lost or recomputing anything expensive, look in `<dir>/.snapshot/` (hidden: `ls` won't
   list it, open it by name) and restore with `cp`. Anything older: ask the user to request a restore from backup
   through cluster support.

| Storage | Path | For | Snapshots | Backups | Deleted |
| --- | --- | --- | --- | --- | --- |
| home | `$HOME` | personal files; 50 GB, 500k files | hourly, daily | nightly | with the account |
| project | `/cluster/project/<group>` | long-term, critical data | hourly, daily | several a week, kept 90 days | never |
| work | `/cluster/work/<group>` | large files, fast I/O | none | several a week | never |
| scratch | `/cluster/scratch/$USER` | transient data; 2.5 TB, 1M files | none | none | after about two weeks |
| `$TMPDIR` | node-local, per job | many-small-file I/O in a job | none | none | when the job ends |
