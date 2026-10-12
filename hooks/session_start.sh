#!/bin/sh
# SessionStart hook: on Euler, print this session's node, allocation and the user's settings, then the always-on
# rules; tag the jobs this session submits and record the session for `euler-jobs`.
# Its stdout joins the agent's context. Silent elsewhere; always exits 0.
# The allocation comes from the job's SLURM_* variables: asking slurmctld can take longer than the hook may.

host=$(hostname 2>/dev/null) || exit 0
case "$host" in eu-*) ;; *) exit 0 ;; esac
[ -d /cluster/home ] || exit 0

payload=$(cat)
field() { printf '%s' "$payload" | sed -n "s/.*\"$1\" *: *\"\\([^\"]*\\)\".*/\\1/p" | head -n 1; }

case "$host" in
eu-login-*)
	echo "Euler: login node $host, no allocation."
	;;
*)
	if [ -z "${SLURM_JOB_ID:-}" ]; then
		echo "Euler: compute node $host, SLURM_JOB_ID unset; find the allocation with \`squeue --me -w $host\`."
	else
		cpus=${SLURM_CPUS_ON_NODE:-?}
		mb=${SLURM_MEM_PER_NODE:-$((${SLURM_MEM_PER_CPU:-0} * ${SLURM_CPUS_ON_NODE:-0}))}
		if [ "$mb" -gt 0 ] && [ $((mb % 1024)) -eq 0 ]; then mem="$((mb / 1024))G"; else mem="${mb}M"; fi
		left=""
		if [ -n "${SLURM_JOB_END_TIME:-}" ]; then
			s=$((SLURM_JOB_END_TIME - $(date +%s)))
			left=", $((s / 3600))h $((s % 3600 / 60))m left"
		fi
		echo "Euler: compute node $host, job $SLURM_JOB_ID: cpus=$cpus, mem=$mem, gpus=${SLURM_GPUS_ON_NODE:-0}$left."
	fi
	;;
esac

# The user's own setup, from the plugin settings
group=${CLAUDE_PLUGIN_OPTION_GROUP:-}
root=${CLAUDE_PLUGIN_OPTION_WORK_ROOT:-}
[ -n "$group" ] && echo "Group storage: /cluster/project/$group, /cluster/work/$group."
[ -n "$root" ] && echo "Work root: $root."
[ -n "${CLAUDE_PLUGIN_OPTION_NOTES:-}" ] && echo "User's notes: $CLAUDE_PLUGIN_OPTION_NOTES"

# Tag this session's jobs and record the session, so `euler-jobs` can tell which session submitted what
sid=$(field session_id)
if [ -n "$sid" ] && [ -n "${CLAUDE_ENV_FILE:-}" ]; then
	tag="claude:$(printf '%s' "$sid" | cut -c1-8)"
	data="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugins/data/euler-hpc}/sessions"
	mkdir -p "$data" && find "$data" -type f -mtime +30 -delete 2>/dev/null
	window=""
	[ -n "${TMUX_PANE:-}" ] && window=$(tmux display-message -p -t "$TMUX_PANE" '#S:#I #W' 2>/dev/null | tr -d '\n')
	{
		echo "session=$sid"
		echo "cwd=$(field cwd)"
		echo "transcript=$(field transcript_path)"
		echo "host=$host"
		echo "pid=$(ps -o ppid= -p "$PPID" 2>/dev/null | tr -d ' ')"
		echo "job=${SLURM_JOB_ID:-}"
		echo "tmux=$window"
	} >"$data/$sid"
	cat >>"$CLAUDE_ENV_FILE" <<EOF
export EULER_HPC_SESSION='$sid' EULER_HPC_TAG='$tag' EULER_HPC_DATA='$data'
sbatch() { command sbatch --comment="\$EULER_HPC_TAG" "\$@"; }
salloc() { command salloc --comment="\$EULER_HPC_TAG" "\$@"; }
EOF
	echo "Jobs this session submits with sbatch or salloc carry --comment=$tag; \`euler-jobs\` lists jobs by session."
fi

echo
cat "$(dirname "$0")/session_context.md"
exit 0
