"""Experiment Designer agent — prompt building and config."""

from typing import Any

from subagents.experiment_designer.system_prompt import SYSTEM_PROMPT
from subagents.runner import run_agent

ALLOWED_TOOLS = ["Read", "Glob", "Grep"]
DISALLOWED_TOOLS = ["Edit", "Bash", "WebSearch", "WebFetch"]

RESTRICTED_FILES: dict[str, str] = {
    "eval_science_principles.md": "Orchestrator-only methodological reference.",
    "cot_analyst_interface_contract.md": "Not relevant to this agent.",
    "reviewer_interface_contract.md": "Not relevant to this agent.",
}


async def run_experiment_designer(cwd: str | None = None, **data: Any) -> str:
    """Run the experiment designer agent and return its markdown report."""
    sections = [
        f"## Hypothesis\n\n{data['hypothesis']}",
        f"## Eval Summary\n\n{data['eval_summary']}",
    ]
    if data.get("constraints"):
        sections.append(f"## Constraints\n\n{data['constraints']}")

    prompt = "\n\n".join(sections) + "\n"

    return await run_agent(
        prompt=prompt,
        system_prompt=SYSTEM_PROMPT,
        allowed_tools=ALLOWED_TOOLS,
        disallowed_tools=DISALLOWED_TOOLS,
        agent_name="Experiment designer",
        cwd=cwd,
        restricted_files=RESTRICTED_FILES,
        memory_file=None,
        model=data.get("subagent_model"),
    )
