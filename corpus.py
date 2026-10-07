"""Run every corpus pipeline under pipelines/<shelf>/ on the instance DG_URL names.

Each pipeline is run with `dg run CODE --watch --json`, six at a time, and what is judged
is the last run record in its stream: its message against the outcome the pipeline is meant
to end with. A pipeline ends `succeeded` unless EXPECTED says otherwise, which it does for
every document that fails or completes with errors by design.

Writes one NDJSON record per pipeline -- corpus.passed, corpus.failed or corpus.skipped --
then one corpus.done with the counts.

  uv run python corpus.py
"""

import json
import os
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

import yaml

PIPELINES = Path("pipelines")
DEFAULT_INSTANCE = "http://127.0.0.1:4444"
#: How many runs are watched at once. An instance gives one user eight streams, and the
#: consumers hold theirs for as long as they wait.
PARALLEL = 6
TIMEOUT_SECONDS = 300

#: The outcome a pipeline ends with by design, where that is not `succeeded`.
EXPECTED: dict[str, str] = {
    **dict.fromkeys(
        [
            "deadline-on-a-sensor",
            "docker-compose-failing-up",
            "docker-run-failing-teardown",
            "error-handler",
            "fan-out-fail-fast",
            "fan-out-too-wide",
            "pipeline-run-strict",
            "reconcile-two-sources",
            "retry-budget",
            "retry-budget-exhausted",
            "retry-exponential-backoff",
            "rule-all-done",
            "rule-all-success",
            "rule-always",
            "rule-one-failed",
            "schema-refuses-then-rule",
            "step-timeout",
            "the-shape-is-wrong",
            "timeout-fails-the-step",
        ],
        "failed",
    ),
    **dict.fromkeys(
        [
            "fan-out-continue",
            "fan-out-late-after-continue",
            "one-region-refuses",
            "optional-step",
            "retries",
            "retry-only-transient",
            "retry-with-jitter",
        ],
        "completed_with_errors",
    ),
}

#: A value for each required parameter the corpus leaves without a default.
REQUIRED_VALUES: dict[str, str] = {"day": "2026-01-01", "region": "east", "dataset": "climate"}

#: Documents an instance on this project does not take, and why. setup.sh reports each refusal.
NOT_APPLIED: dict[str, str] = {
    "docker-build-push": "needs ghcr, a registry connection with a push credential",
    "docker-remote-daemon": "needs build-daemon, a remote Docker daemon over TCP and TLS",
    "odk-central-submissions": "needs odk-central, an ODK Central server and an account on it",
    "s3-parquet-to-ingestion": "a preview: needs an adapter pack's modelling-api and ops-webhook",
}

#: Pipelines verify.sh runs itself, or that are not run here, and why.
SKIPPED: dict[str, str] = {
    "http-follow-redirects": "verify.sh runs it with the other playground routes",
    "a-stream-to-read": "verify.sh runs it with the other playground routes",
    "kobo-submissions-to-csv": "needs a KoboToolbox account: an asset_uid and a token",
}

#: Started first: they wait on the topic the producers write to, and
#: kafka-consume-then-transform reads it from the latest offset, so it has to be waiting before
#: anything is produced.
CONSUMERS = ("kafka-consume-then-transform", "kafka-watch-then-transform")

#: Started once the consumers are waiting: they produce to the topic the consumers read.
PRODUCERS = ("report-to-kafka", "kafka-produce-then-consume")

#: Shelves whose pipelines bring containers up on this machine's daemon, run one at a time
#: after the rest: two stacks starting at once contend for the daemon and its host ports.
SERIAL_SHELVES = ("docker", "git")

#: How long the consumers are given to take their first poke.
CONSUMER_HEAD_START_SECONDS = 20


def emit(kind: str, **fields: Any) -> None:
    print(json.dumps({"kind": kind, **fields}), flush=True)


def documents() -> list[tuple[str, Path, dict[str, Any]]]:
    """Every pipeline document on a shelf, with its code: never a triggers document."""
    found = []
    for path in sorted([*PIPELINES.glob("*/*.yaml"), PIPELINES / "hello-world.yaml"]):
        raw = yaml.safe_load(path.read_text())
        if isinstance(raw, dict) and raw.get("kind") == "pipeline":
            found.append((raw["code"], path, raw))
    return found


def flags_for(raw: dict[str, Any], text: str, instance: str, window: str) -> list[str] | str:
    """The flags one run is given, or the reason it cannot be run."""
    flags: list[str] = []
    params = raw.get("params") or {}
    properties = params.get("properties") or {}
    for name, schema in properties.items():
        default = schema.get("default") if isinstance(schema, dict) else None
        if isinstance(default, str) and DEFAULT_INSTANCE in default and instance != DEFAULT_INSTANCE:
            flags += ["-p", f"{name}={default.replace(DEFAULT_INSTANCE, instance)}"]
    for name in params.get("required") or []:
        if "default" in (properties.get(name) or {}):
            continue
        if name not in REQUIRED_VALUES:
            return f"needs a value for its required parameter {name}"
        flags += ["-p", f"{name}={REQUIRED_VALUES[name]}"]
    if "${run.window" in text:
        flags += ["--window", window]
    return flags


def run(code: str, flags: list[str], expected: str) -> dict[str, Any]:
    """Run one pipeline and judge the last run record it streams."""
    command = ["dg", "run", code, "--watch", "--json", *flags]
    try:
        done = subprocess.run(command, capture_output=True, text=True, timeout=TIMEOUT_SECONDS, check=False)
        out = done.stdout
    except subprocess.TimeoutExpired:
        return {"kind": "corpus.failed", "code": code, "expected": expected, "got": f"no end in {TIMEOUT_SECONDS}s"}
    records = [json.loads(line) for line in out.splitlines() if line.startswith("{")]
    settled = [r for r in records if r.get("kind") == "run" and "exit_code" in r]
    if not settled:
        errors = [r.get("message") for r in records if r.get("kind") == "error"]
        return {"kind": "corpus.failed", "code": code, "expected": expected, "got": "no run", "errors": errors}
    last = settled[-1]
    fields = {"code": code, "expected": expected, "got": last.get("message"), "run_id": last.get("run_id")}
    if last.get("message") == expected:
        return {"kind": "corpus.passed", **fields}
    failures = [f"{f.get('step')}: {str(f.get('error'))[-600:]}" for f in last.get("failures") or []]
    return {"kind": "corpus.failed", **fields, "failures": failures[:3]}


def main() -> int:
    instance = os.environ.get("DG_URL", DEFAULT_INSTANCE)
    now = datetime.now(UTC).replace(microsecond=0)
    window = f"{(now - timedelta(days=1)).isoformat()}..{now.isoformat()}"
    counts = {"passed": 0, "failed": 0, "skipped": 0}
    planned: list[tuple[str, list[str], str, str]] = []
    for code, path, raw in documents():
        reason = NOT_APPLIED.get(code) or SKIPPED.get(code)
        flags = flags_for(raw, path.read_text(), instance, window) if reason is None else reason
        if isinstance(flags, str):
            counts["skipped"] += 1
            emit("corpus.skipped", code=code, path=str(path), reason=flags)
            continue
        planned.append((code, flags, EXPECTED.get(code, "succeeded"), path.parent.name))

    def settle(result: dict[str, Any]) -> None:
        counts[result["kind"].split(".")[1]] += 1
        print(json.dumps(result), flush=True)

    serial = [one[:3] for one in planned if one[3] in SERIAL_SHELVES]
    parallel = [one[:3] for one in planned if one[3] not in SERIAL_SHELVES]
    consumers = [one for one in parallel if one[0] in CONSUMERS]
    producers = [one for one in parallel if one[0] in PRODUCERS]
    rest = [one for one in parallel if one[0] not in CONSUMERS and one[0] not in PRODUCERS]
    with ThreadPoolExecutor(max_workers=len(consumers) or 1) as waiting:
        pending = [waiting.submit(run, *one) for one in consumers]
        time.sleep(CONSUMER_HEAD_START_SECONDS if consumers else 0)
        with ThreadPoolExecutor(max_workers=PARALLEL) as pool:
            for result in pool.map(lambda one: run(*one), [*producers, *rest]):
                settle(result)
        for future in pending:
            settle(future.result())
    for one in serial:
        settle(run(*one))
    emit("corpus.done", **counts)
    return 0 if counts["failed"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
