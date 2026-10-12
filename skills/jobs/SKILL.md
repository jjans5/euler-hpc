---
name: jobs
description: Overview of your Slurm jobs on Euler, grouped by the Claude Code session that submitted each one.
disable-model-invocation: true
allowed-tools: Bash(euler-jobs *)
---

!`euler-jobs --session ${CLAUDE_SESSION_ID}`

Show the overview above as it is, in a code block. Under it, in at most three lines, point out what needs the user:
jobs still queued or running whose session is closed, jobs that failed, ran out of time or memory, and jobs pending
for long. Never suggest cancelling a job that hosts a session.
