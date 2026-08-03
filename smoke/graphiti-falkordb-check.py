#!/usr/bin/env python3
"""Proves the Graphiti -> FalkorDB driver swap end to end.

Our memory pipeline already emits Graphiti episodes; FalkorDB is an official
Graphiti backend (same API, falkor:// URI). If this prints GREEN, the
mandated memory layer and our existing episode model are one thing.

pip install "graphiti-core[falkordb]"
Needs OPENAI_API_KEY (Graphiti builds the graph via LLM + embeddings).
"""
import asyncio
import os
from datetime import datetime, timezone

from graphiti_core import Graphiti
from graphiti_core.nodes import EpisodeType


async def main() -> None:
    graphiti = Graphiti(uri=os.environ.get("FALKOR_URI", "falkor://localhost:6379"))
    await graphiti.build_indices_and_constraints()
    await graphiti.add_episode(
        name="prep_check",
        episode_body=(
            "While reading an agent session about the signal pipeline, the user "
            "spoke a raw note connecting it to an earlier residency idea."
        ),
        episode_type=EpisodeType.text,
        source_description="hackathon prep check",
        reference_time=datetime.now(timezone.utc),
    )
    results = await graphiti.search("what connects to the residency idea?")
    assert results, "search returned nothing"
    print("GRAPHITI_FALKORDB_GREEN")


asyncio.run(main())
