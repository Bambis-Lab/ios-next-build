#!/usr/bin/env bash
# Lightweight CI runtime telemetry. This file must not alter test semantics.
set -u

CI_RUNTIME_DIR="${CI_RUNTIME_DIR:-.ci-runtime}"
CI_RUNTIME_SCOPE="${CI_RUNTIME_SCOPE:-default}"
mkdir -p "$CI_RUNTIME_DIR"

runtime_now_ns() {
  python3 - <<'PY'
import time
print(time.time_ns())
PY
}

runtime_safe_name() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9_.-' '_'
}

runtime_start() {
  local name safe
  name="$1"
  safe="$(runtime_safe_name "$name")"
  runtime_now_ns > "$CI_RUNTIME_DIR/start-$safe"
}

runtime_end() {
  local name safe start_ns end_ns
  name="$1"
  safe="$(runtime_safe_name "$name")"
  test -f "$CI_RUNTIME_DIR/start-$safe" || return 0
  start_ns="$(cat "$CI_RUNTIME_DIR/start-$safe")"
  end_ns="$(runtime_now_ns)"
  python3 - "$CI_RUNTIME_DIR/events.jsonl" "$CI_RUNTIME_SCOPE" "$name" "$start_ns" "$end_ns" <<'PY'
import json, sys
path, scope, name, start_ns, end_ns = sys.argv[1:]
start_ns, end_ns = int(start_ns), int(end_ns)
event = {
    "type": "duration",
    "scope": scope,
    "name": name,
    "start_ns": start_ns,
    "end_ns": end_ns,
    "seconds": round((end_ns - start_ns) / 1_000_000_000, 6),
}
with open(path, "a", encoding="utf-8") as handle:
    handle.write(json.dumps(event, sort_keys=True) + "\n")
PY
  rm -f "$CI_RUNTIME_DIR/start-$safe"
}

runtime_count() {
  local name delta
  name="$1"
  delta="${2:-1}"
  python3 - "$CI_RUNTIME_DIR/events.jsonl" "$CI_RUNTIME_SCOPE" "$name" "$delta" <<'PY'
import json, sys, time
path, scope, name, delta = sys.argv[1:]
event = {
    "type": "count",
    "scope": scope,
    "name": name,
    "delta": int(delta),
    "timestamp_ns": time.time_ns(),
}
with open(path, "a", encoding="utf-8") as handle:
    handle.write(json.dumps(event, sort_keys=True) + "\n")
PY
}

runtime_render_json() {
  local output
  output="$1"
  python3 - "$CI_RUNTIME_DIR/events.jsonl" "$output" "$CI_RUNTIME_SCOPE" <<'PY'
import json, os, sys
from collections import defaultdict
from datetime import datetime, timezone

events_path, output_path, scope = sys.argv[1:]
events = []
if os.path.exists(events_path):
    with open(events_path, encoding="utf-8") as handle:
        events = [json.loads(line) for line in handle if line.strip()]

durations = defaultdict(list)
counters = defaultdict(int)
for event in events:
    if event.get("scope") != scope:
        continue
    if event.get("type") == "duration":
        durations[event["name"]].append(float(event["seconds"]))
    elif event.get("type") == "count":
        counters[event["name"]] += int(event["delta"])

payload = {
    "schema_version": 1,
    "scope": scope,
    "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    "durations": {
        name: {
            "count": len(values),
            "total_seconds": round(sum(values), 6),
            "min_seconds": round(min(values), 6),
            "max_seconds": round(max(values), 6),
        }
        for name, values in sorted(durations.items())
    },
    "counters": dict(sorted(counters.items())),
    "events": [event for event in events if event.get("scope") == scope],
}
with open(output_path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
}
