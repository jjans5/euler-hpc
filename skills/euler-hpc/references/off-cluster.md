# Driving Euler from another machine

For a session that runs on a laptop or workstation, not on Euler (`hostname` does not start with `eu-` and
`$SLURM_JOB_ID` is unset). Everything in the skill still applies; each command just goes through `essh`.

## Why a wrapper

All sessions on one machine share **one** SSH ControlMaster connection (host alias `euler-agents`). Two limits
make raw `ssh` unsafe there:

- **Euler allows about 10 concurrent sessions per connection.** Beyond that it answers `Session open refused by
  peer`, for every session on the machine, the user's own terminal included.
- **A killed local `ssh` does not stop the remote command.** `timeout 60 ssh …` or a cancelled tool call leaves the
  command running on Euler, holding its slot until it ends. Orphaned pollers have filled all ten slots before.

`essh` (in this plugin's `bin/`, on the agent's `PATH`) caps this machine at 6 sessions and queues the rest,
retries refused sessions, runs the command under `timeout` **on Euler** so the slot is freed whatever happens
locally, and logs to `/tmp/essh-<uid>/log`.

```bash
essh 'cmd1; cmd2'                    # default 120 s limit, enforced on Euler too
essh -t 600 'cmd'                    # at most 900 s; anything longer is an sbatch job
cat file.py | essh 'cat > /cluster/work/<group>/…/file.py'
rsync -av -e essh src/ euler-agents:/cluster/work/<group>/…/
essh 'bash -s' < "$(command -v euler-caps)"      # run a local script on Euler
```

Exit codes: 124 hit the timeout, 75 no free slot within 10 min, 78 no username configured, 255 ssh failure (it
says when the shared connection is down).

## Rules

- **Batch** related lookups into one call (`echo "== x"; …; echo "== y"; …`). Single-quote the remote command so
  `$VARS` and globs expand on Euler.
- Each call is a fresh shell: no persistent `cd`; prefix commands with `cd <absolute path> &&`.
- **Polling:** one poller per batch of jobs, `sleep` ≥ 60 s between checks, one `sacct` call for all job IDs, stopped
  when the jobs end. Never a loop without a sleep.
- Interactive programs (`top`, `less`, `vim`, `tail -f`, `watch`) hang the call until it times out.
- To iterate on a node, hold an allocation and run steps into it (skill: "Interactive allocation"); each
  `srun --jobid` call occupies one `essh` session while it runs and is bound by the same timeout.

## Setup, once per machine

`essh` needs the user's ETH username and has no default. Ask for it; never guess it from the local login name (a
wrong name only produces failed logins). It is read, in this order, from a `Host euler-agents` block in
`~/.ssh/config`, the `EULER_USER` environment variable, or a line `EULER_USER=<name>` in
`~/.config/euler-hpc/config.env`. The one-line config file is enough: without a Host block, `essh` supplies the
other settings itself. A Host block, if the user prefers one:

```
Host euler-agents
    HostName euler.ethz.ch
    User <eth-username>
    ControlMaster auto
    ControlPath /tmp/ssh-mux-%i-%n
    ControlPersist 28800
    ServerAliveInterval 60
    ServerAliveCountMax 3
```

Then try `essh 'hostname; whoami'`. Where Euler accepts the machine's SSH key without MFA, that call opens the
shared connection itself. Where a login needs password and MFA, it fails and prints the exact `euler-reconnect`
command: give it to the user to run in their own terminal (ETH network or VPN). Agents cannot answer the prompt,
so do not retry in a loop. The connection then lasts until 8 h after its last session closes. `euler-reconnect`
also clears leftover sessions that still count against the cap.

## What differs from a session on Euler

- The session-start context does not appear off Euler: read
  `${CLAUDE_PLUGIN_ROOT}/hooks/session_context.md` for the always-on rules (storage, snapshots, cancelling).
- `euler-jobs` and its session tags only see jobs submitted from sessions on Euler. Name jobs after the task
  (`-J <task>-…`) and keep the IDs in the task's notes.
- The agent's `/tmp` and scratch directory are on the local machine, not on Euler: inputs, scripts and logs for a
  job have to be copied (`rsync -e essh`) to Euler storage first.
