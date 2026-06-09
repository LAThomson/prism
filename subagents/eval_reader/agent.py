"""Eval Reader agent — prompt building and config."""

from typing import Any

from subagents.eval_reader.system_prompt import SYSTEM_PROMPT
from subagents.runner import run_agent

ALLOWED_TOOLS = ["Read", "Glob", "Grep"]
DISALLOWED_TOOLS = ["Edit", "Bash", "WebSearch", "WebFetch"]

RESTRICTED_FILES: dict[str, str] = {
    "eval_science_principles.md": "Orchestrator-only methodological reference.",
    "cot_analyst_interface_contract.md": "Not relevant to this agent.",
    "experiment_designer_interface_contract.md": "Not relevant to this agent.",
    "reviewer_interface_contract.md": "Not relevant to this agent.",
}


async def run_eval_reader(cwd: str | None = None, **data: Any) -> str:
    """Run the eval reader agent and return its markdown report."""
    prompt = f"## Eval Path\n\n{data['eval_path']}\n"
    return await run_agent(
        prompt=prompt,
        system_prompt=SYSTEM_PROMPT,
        allowed_tools=ALLOWED_TOOLS,
        disallowed_tools=DISALLOWED_TOOLS,
        agent_name="Eval reader",
        cwd=cwd,
        restricted_files=RESTRICTED_FILES,
        memory_file=None,
        model=data.get("subagent_model"),
    )
