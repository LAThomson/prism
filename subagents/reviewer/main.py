"""CLI entry point for the Reviewer agent."""

import os
import sys

sys.path.insert(
    0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
)

from subagents.cli import AgentCLIConfig, run_cli  # noqa: E402
from subagents.reviewer.agent import run_reviewer  # noqa: E402

if __name__ == "__main__":
    run_cli(
        AgentCLIConfig(
            name="Reviewer",
            required_fields=[
                "hypothesis",
                "research_question",
                "iterations",
                "draft_conclusion",
            ],
            directory_field=None,
            run_fn=run_reviewer,
        )
    )
