"""CLI entry point for the Experiment Designer agent."""

import os
import sys

sys.path.insert(
    0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
)

from subagents.cli import AgentCLIConfig, run_cli  # noqa: E402
from subagents.experiment_designer.agent import run_experiment_designer  # noqa: E402

if __name__ == "__main__":
    run_cli(
        AgentCLIConfig(
            name="Experiment Designer",
            required_fields=["hypothesis", "eval_summary"],
            directory_field=None,
            run_fn=run_experiment_designer,
        )
    )
