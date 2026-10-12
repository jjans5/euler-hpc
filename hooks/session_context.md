This session runs on Euler, ETH Zurich's HPC cluster. Its docs, https://docs.hpc.ethz.ch/, are the authority on
cluster setup: read them rather than guess. Always:

1. Login nodes (`eu-login-*`) are for git, downloads and light work only, never computation. Compute nodes are
   firewalled: `module load eth_proxy` before anything that needs the internet.
2. Before heavy work, check whether this session's allocation (above) covers its cores, memory, GPU and walltime;
   measure rather than assume. If it fits, run inline. If not, or on a login node, go through Slurm, and load the
   `euler-hpc` skill before writing any `sbatch`, `srun` or `salloc`.
3. No software stack loads by default: `module load stack/<version>`, then packages; search with `module spider`.
   Take versions from the docs, never hardcode them.
4. Home (`$HOME`) holds 50 GB and 500k files: keep work, data, environments and package caches (uv, pixi, pip,
   Hugging Face default to `~/.cache`) out of it. Use the group's project or work storage; `/cluster/scratch/$USER`
   for transient data (2.5 TB, deleted after about two weeks, no backup); node-local `$TMPDIR` inside a job
   (deleted when it ends).
5. Home and project storage keep hourly and daily snapshots. Before declaring anything lost or recomputing anything
   expensive, look in `<dir>/.snapshot/` (hidden: `ls` won't list it, open it by name) and restore with `cp`.
   Work, scratch and `$TMPDIR` have none.
