"""CoT Analyst agent — prompt building and config."""

import json
from typing import Any

from subagents.cot_analyst.system_prompt import SYSTEM_PROMPT
from subagents.runner import run_agent

ALLOWED_TOOLS = ["Bash", "Read", "Write", "Glob", "Grep"]
DISALLOWED_TOOLS = ["Edit", "WebSearch", "WebFetch"]

# The CoT Analyst must never read anything that could reveal the hypothesis
# or the experimental design framing. This holds for both call modes.
RESTRICTED_FILES: dict[str, str] = {
    "eval_science_principles.md": (
        "Contains hypothesis-informing methodological principles. "
        "The analyst must not access this to prevent confirmation bias."
    ),
    "reviewer_interface_contract.md": "Not relevant to this agent.",
    "experiment_designer_interface_contract.md": (
        "Contains experimental design framing. Not relevant to this agent."
    ),
}


async def run_cot_analyst(cwd: str | None = None, **data: Any) -> str:
    """Run the CoT analyst agent and return its markdown report."""
    mode = data["mode"]
    eval_summary = data["eval_summary"]
    transcript_source = data["transcript_source"]

    sections = [
        f"## Mode\n\n{mode}",
        f"## Eval Summary\n\n{eval_summary}",
    ]

    if isinstance(transcript_source, dict):
        sections.append(
            f"## Transcript Source\n\n```json\n{json.dumps(transcript_source, indent=2)}\n```"
        )
    else:
        sections.append(f"## Transcript Source\n\n{transcript_source}")

    if data.get("scanning_model"):
        sections.append(f"## Scanning Model\n\n{data['scanning_model']}")

    if data.get("constraints"):
        sections.append(
            f"## Constraints\n\n```json\n{json.dumps(data['constraints'], indent=2)}\n```"
        )

    if data.get("artefacts_dir"):
        sections.append(f"## Artefacts Directory\n\n{data['artefacts_dir']}")

    prompt = "\n\n".join(sections) + "\n"

    return await run_agent(
        prompt=prompt,
        system_prompt=SYSTEM_PROMPT,
        allowed_tools=ALLOWED_TOOLS,
        disallowed_tools=DISALLOWED_TOOLS,
        agent_name="CoT analyst",
        cwd=cwd,
        restricted_files=RESTRICTED_FILES,
        # Stateless across invocations: no memory file, so no findings leak
        # between investigations and the hypothesis firewall holds.
        memory_file=None,
        restrict_writes_to_memory=False,
        model=data.get("subagent_model"),
    )
