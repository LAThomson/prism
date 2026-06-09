"""Reviewer agent — prompt building and config."""

import json
from typing import Any

from subagents.reviewer.system_prompt import SYSTEM_PROMPT
from subagents.runner import run_agent

ALLOWED_TOOLS = ["Read", "Glob", "Grep"]
DISALLOWED_TOOLS = ["Edit", "Bash", "WebSearch", "WebFetch"]

RESTRICTED_FILES: dict[str, str] = {
    "eval_science_principles.md": "Orchestrator-only methodological reference.",
    "cot_analyst_interface_contract.md": "Not relevant to this agent.",
    "experiment_designer_interface_contract.md": "Not relevant to this agent.",
}


async def run_reviewer(cwd: str | None = None, **data: Any) -> str:
    """Run the reviewer agent and return its adversarial assessment."""
    iterations_json = json.dumps(data["iterations"], indent=2)
    sections = [
        f"## Research Question\n\n{data['research_question']}",
        f"## Hypothesis\n\n{data['hypothesis']}",
        f"## Iterations\n\n```json\n{iterations_json}\n```",
        f"## Draft Conclusion\n\n{data['draft_conclusion']}",
    ]

    prompt = "\n\n".join(sections) + "\n"

    return await run_agent(
        prompt=prompt,
        system_prompt=SYSTEM_PROMPT,
        allowed_tools=ALLOWED_TOOLS,
        disallowed_tools=DISALLOWED_TOOLS,
        agent_name="Reviewer",
        cwd=cwd,
        restricted_files=RESTRICTED_FILES,
        memory_file=None,
        model=data.get("subagent_model"),
    )
