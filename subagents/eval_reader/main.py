"""CLI entry point for the Eval Reader agent."""

import os
import sys

sys.path.insert(
    0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
)

from subagents.cli import AgentCLIConfig, run_cli  # noqa: E402
from subagents.eval_reader.agent import run_eval_reader  # noqa: E402

if __name__ == "__main__":
    run_cli(
        AgentCLIConfig(
            name="Eval Reader",
            required_fields=["eval_path"],
            directory_field="eval_path",
            run_fn=run_eval_reader,
        )
    )
