#!/bin/sh
# Test bin/euler-jobs against stub `squeue` and `sacct` and a recorded session. Runs anywhere with python3.
set -eu

jobs_cmd="$(cd "$(dirname "$0")/.." && pwd)/bin/euler-jobs"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/data"

cat >"$tmp/bin/squeue" <<'EOF'
#!/bin/sh
echo '101|train|RUNNING|1:00|4:00:00|eu-a2p-1|claude:aaaaaaaa'
echo '102|tunnel|RUNNING|2:00|5-00:00:00|eu-a2p-1|52951'
EOF
cat >"$tmp/bin/sacct" <<'EOF'
#!/bin/sh
echo '101|train|RUNNING|00:01:00|04:00:00|Unknown|claude:aaaaaaaa'
echo '99|prep|COMPLETED|00:05:00|01:00:00|2026-01-01T12:34:56|claude:bbbbbbbb'
echo '98|old|CANCELLED by 123|00:00:01|01:00:00|2026-01-01T10:00:00|'
EOF
chmod +x "$tmp/bin/squeue" "$tmp/bin/sacct"
printf 'session=aaaaaaaa-1111\ncwd=/c/repo\ntranscript=/nonexistent\nhost=elsewhere\npid=1\ntmux=main:2 work\njob=102\n' \
	>"$tmp/data/aaaaaaaa-1111"

run() { env HOME="$tmp" PATH="$tmp/bin:$PATH" EULER_HPC_DATA="$tmp/data" EULER_HPC_SESSION=aaaaaaaa-1111 \
	python3 "$jobs_cmd" "$@"; }
fail() { echo "FAIL: $1"; printf '%s\n' "$out"; exit 1; }

out=$(run)
echo "$out" | grep -q "Session aaaaaaaa  tmux main:2 work  /c/repo  (on elsewhere, no transcript)  <- this session" \
	|| fail "session header"
echo "$out" | grep -q "^  101 .*train .*RUNNING" || fail "queued job"
echo "$out" | grep -q "Session bbbbbbbb  ?  (unknown session)" || fail "unrecorded session"
echo "$out" | grep -q "^  99 .*COMPLETED .*ended 12:34" || fail "ended job"
echo "$out" | grep -q "^  98 .*CANCELLED " || fail "state shortened"
echo "$out" | grep -A3 "Not from a tagged" | grep -q "^  102 " || fail "untagged job"
[ "$(echo "$out" | grep -c '^  101 ')" -eq 1 ] || fail "job listed twice"
echo "$out" | grep -q "^  102 .*hosts session aaaaaaaa" || fail "hosting job"

out=$(run --mine)
echo "$out" | grep -q "^  101 " || fail "--mine keeps own job"
! echo "$out" | grep -q "^  99 \|^  102 " || fail "--mine drops others"

echo "ok"
