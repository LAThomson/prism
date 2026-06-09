"""CLI entry point for the CoT Analyst agent."""

import os
import sys

sys.path.insert(
    0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
)

from subagents.cli import AgentCLIConfig, run_cli  # noqa: E402
from subagents.cot_analyst.agent import run_cot_analyst  # noqa: E402

if __name__ == "__main__":
    run_cli(
        AgentCLIConfig(
            name="CoT Analyst",
            required_fields=["mode", "eval_summary", "transcript_source"],
            directory_field=None,
            run_fn=run_cot_analyst,
        )
    )
