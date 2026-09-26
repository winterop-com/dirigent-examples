"""Apply every document under pipelines/, however deep, to the instance DG_URL names.

This is `dg dev --seed pipelines` against an instance that is already running: the same
dirigent_cli.seeding walk, so a document's carried connections and schemas are created on
the instance and the document is applied without them, and a schedule a first apply creates
is created paused. The walk runs twice, so a document that requires a pipeline later in the
walk finds it the second time.

The corpus's carried connections address the playground at 127.0.0.1:3333. Once the walk is
done, each of them is rewritten to address DG_URL instead, one config per code: where two
documents carry the same code, the fields of both are kept.

Writes one NDJSON record per line: the walk's own records, each with the pass it came from,
then one seed.readdressed record per connection rewritten.
"""

import asyncio
import json
import os
import sys
from collections.abc import Mapping
from pathlib import Path
from typing import Any

from dirigent_cli.seeding import seed_directories
from dirigent_client import Dirigent
from dirigent_core.documents import is_document, readable

PASSES = 2
DEFAULT_PLAYGROUND = "http://127.0.0.1:3333/api/v1/playground"


def carried_connections(root: Path) -> dict[str, dict[str, Any]]:
    """Every connection the documents carry that addresses the default playground, merged by code."""
    merged: dict[str, dict[str, Any]] = {}
    for _path, raw in readable(root):
        declared = raw.get("connections") if is_document(raw) else None
        if not isinstance(declared, Mapping):
            continue
        for code, body in declared.items():
            config = dict(body.get("config") or {})
            if str(config.get("base_url", "")).startswith(DEFAULT_PLAYGROUND):
                merged.setdefault(code, {}).update(config)
    return merged


async def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else "pipelines")
    url = os.environ["DG_URL"]
    async with Dirigent(url=url, token=os.environ["DG_TOKEN"]) as client:
        for number in range(1, PASSES + 1):
            async for record in seed_directories(client, [root]):
                print(json.dumps({**record, "pass": number}, default=str), flush=True)
        playground = f"{url}/api/v1/playground"
        for code, config in sorted(carried_connections(root).items()):
            config["base_url"] = config["base_url"].replace(DEFAULT_PLAYGROUND, playground)
            await client.connections.update(code, config=config)
            print(json.dumps({"kind": "seed.readdressed", "connection": code, "base_url": config["base_url"]}))
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
