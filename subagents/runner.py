"""Shared Agent SDK runner for all sub-agents."""

import os
from typing import Any

from claude_agent_sdk import (
    ClaudeAgentOptions,
    CLIConnectionError,
    CLINotFoundError,
    HookMatcher,
    ProcessError,
    ResultMessage,
    ThinkingConfig,
    query,
)

_PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Model every sub-agent runs on unless the invocation overrides it via the
# `subagent_model` input field. Kept as a single default so the override is the
# only thing that ever varies (e.g. a less refusal-prone model on a
# dangerous-capability eval, or a cheaper/weaker model on the user's request).
# Defaults to the most capable Opus tier: per-token cost is equal across Opus
# models, so there is no reason to run the sub-agents on a weaker one — the extra
# capability sharpens the Explorer's site reasoning and the Analyst's scanner /
# stats work, which is where investigation quality is won. (A Sonnet-class model
# is the natural cost/speed downgrade via `subagent_model` if ever wanted.)
DEFAULT_MODEL = "claude-opus-4-8"

# Extended-thinking config every sub-agent runs with unless the invocation
# overrides it via the `subagent_thinking` input field. Adaptive thinking lets
# the model scale reasoning depth to the task on its own — so the Explorer's
# site reasoning and the Analyst's scanner/stats work draw deeply, while the
# Executor's mechanical "run these conditions" work naturally draws little.
# Adaptive is supported on Opus 4.6+ (so it holds for the 4.8 default and any
# reasonable `subagent_model` override) and is in fact the CLI default there; we
# set it explicitly so the behaviour is pinned in the repo rather than left to
# the CLI/model version, and so it can be overridden per invocation (e.g.
# {"type": "disabled"} or {"type": "enabled", "budget_tokens": N}) the same way
# `subagent_model` is — e.g. when overriding to a model without adaptive support.
DEFAULT_THINKING: ThinkingConfig = {"type": "adaptive"}

_MEMORY_INSTRUCTIONS = """\
## Agent Memory

You have a persistent memory file at `{memory_path}`. Its contents are \
included below (if any). You may append observations, lessons learned, \
or notes for future invocations by writing to this file. **Append only** — \
you must preserve all existing content and add new entries at the end. \
The file will be blocked if you attempt to remove or rewrite existing content.

{memory_content}
---

"""


_FOREGROUND_INSTRUCTIONS = """

## Foreground execution only

Run every command in the foreground and wait for it to finish before \
continuing. Never background a task — do not set `run_in_background: true`, \
and do not use a trailing `&` or `nohup`. Long-running commands (evals, \
scripts) are expected; run them in the foreground and wait. Backgrounding \
breaks the scaffold's assumption that a step has completed, and its outputs \
exist, before the next step begins.
"""


def _build_hooks(
    agent_name: str,
    restricted_files: dict[str, str],
    memory_abs_path: str | None,
    restrict_writes_to_memory: bool,
) -> dict[str, Any] | None:
    """Build PreToolUse hooks for file access control and memory.

    Args:
        agent_name: Human-readable agent name for error messages.
        restricted_files: Mapping of filename patterns to denial reasons.
        memory_abs_path: Absolute path to the agent's memory.md, or None.
        restrict_writes_to_memory: If True, block all writes except to
            memory.md. If False, only enforce append-only on memory.md.

    Returns:
        A hooks dict suitable for ClaudeAgentOptions, or None if no
        hooks are needed.
    """
    read_hooks: list[Any] = []
    write_hooks: list[Any] = []

    # --- Read hook: allow memory.md, then check restricted files ---
    if restricted_files or memory_abs_path:

        async def check_read_access(
            input_data: dict, tool_use_id: str, context: dict
        ) -> dict:
            file_path = input_data.get("tool_input", {}).get("file_path", "")
            # Always allow reading the agent's own memory file.
            if memory_abs_path and os.path.abspath(file_path) == memory_abs_path:
                return {}
            for pattern, reason in restricted_files.items():
                if file_path.endswith(pattern):
                    return {
                        "decision": "block",
                        "reason": (
                            f"[{agent_name}] Access denied: {pattern} — {reason}"
                        ),
                    }
            return {}

        read_hooks.append(check_read_access)

    # --- Write hook: append-only memory, optional general write restriction ---
    if memory_abs_path or restrict_writes_to_memory:

        async def check_write_access(
            input_data: dict, tool_use_id: str, context: dict
        ) -> dict:
            tool_input = input_data.get("tool_input", {})
            file_path = tool_input.get("file_path", "")
            is_memory = memory_abs_path and (
                os.path.abspath(file_path) == memory_abs_path
            )

            if is_memory:
                # Enforce append-only: new content must start with existing.
                new_content = tool_input.get("content", "")
                try:
                    with open(memory_abs_path) as f:
                        existing = f.read()
                except FileNotFoundError:
                    existing = ""
                if existing and not new_content.startswith(existing):
                    return {
                        "decision": "block",
                        "reason": (
                            f"[{agent_name}] memory.md is append-only. "
                            "You must preserve all existing content and "
                            "add new entries at the end."
                        ),
                    }
                return {}

            if restrict_writes_to_memory:
                return {
                    "decision": "block",
                    "reason": (
                        f"[{agent_name}] Write access is restricted to memory.md only."
                    ),
                }
            return {}

        write_hooks.append(check_write_access)

    # --- Bash hook: forbid backgrounding so each step runs to completion ---
    # Applies to every sub-agent, and is scoped to this Agent SDK query only, so
    # it never affects the orchestrator or any other Claude Code session.
    async def check_no_background(
        input_data: dict, tool_use_id: str, context: dict
    ) -> dict:
        if input_data.get("tool_input", {}).get("run_in_background"):
            return {
                "decision": "block",
                "reason": (
                    f"[{agent_name}] Backgrounding is disabled for sub-agents. "
                    "Run the command in the foreground and wait for it to "
                    "finish; long-running commands are expected."
                ),
            }
        return {}

    bash_hooks = [check_no_background]

    matchers = []
    if read_hooks:
        matchers.append(HookMatcher(matcher="Read", hooks=read_hooks))
    if write_hooks:
        matchers.append(HookMatcher(matcher="Write", hooks=write_hooks))
    if bash_hooks:
        matchers.append(HookMatcher(matcher="Bash", hooks=bash_hooks))
    return {"PreToolUse": matchers}


async def run_agent(
    prompt: str,
    system_prompt: str,
    allowed_tools: list[str],
    disallowed_tools: list[str],
    agent_name: str,
    cwd: str | None = None,
    restricted_files: dict[str, str] | None = None,
    memory_file: str | None = None,
    restrict_writes_to_memory: bool = True,
    model: str | None = None,
    thinking: ThinkingConfig | None = None,
) -> str:
    """Run an Agent SDK agent and return its output.

    Args:
        prompt: The user prompt to send to the agent.
        system_prompt: The system prompt defining agent behaviour.
        allowed_tools: Tools the agent may use.
        disallowed_tools: Tools explicitly denied (defense-in-depth).
        agent_name: Human-readable name for error messages.
        cwd: Working directory for the agent. Defaults to project root.
        restricted_files: Optional mapping of filename patterns to denial
            reasons. Reads of matching files are blocked with the reason
            shown to the agent.
        memory_file: Optional path to the agent's memory.md, relative to
            the project root. Enables persistent memory (append-only writes,
            content injected into prompt).
        restrict_writes_to_memory: If True (default), block all writes
            except to memory.md. Set to False for agents that need general
            write access (e.g., the transcript analyst writing scripts).
        model: The Claude model this sub-agent runs on. If None, falls back
            to DEFAULT_MODEL. Set per-invocation (via the `subagent_model`
            input field) to override the default — e.g. a less refusal-prone
            model on a dangerous-capability eval, or a cheaper model on
            request.
        thinking: Extended-thinking configuration for this sub-agent. If None,
            falls back to DEFAULT_THINKING (adaptive). Set per-invocation (via
            the `subagent_thinking` input field) to override — e.g.
            {"type": "disabled"} to switch thinking off, or
            {"type": "enabled", "budget_tokens": N} for a fixed budget on a
            model that doesn't support adaptive thinking.

    Returns:
        The agent's output as a string.

    Raises:
        RuntimeError: If the agent produces no output or the SDK fails.
    """
    working_dir = cwd or _PROJECT_ROOT

    # Append the shared foreground-execution rule to every sub-agent's system
    # prompt (mirrors the _MEMORY_INSTRUCTIONS pattern): sub-agents must run
    # tasks in the foreground so each step completes before the next begins.
    system_prompt = system_prompt + _FOREGROUND_INSTRUCTIONS

    # --- Memory injection ---
    memory_abs_path: str | None = None
    if memory_file:
        memory_abs_path = os.path.join(_PROJECT_ROOT, memory_file)
        try:
            with open(memory_abs_path) as f:
                memory_content = f.read().strip()
        except FileNotFoundError:
            memory_content = "(empty — no notes from previous runs)"
        prompt = (
            _MEMORY_INSTRUCTIONS.format(
                memory_path=memory_file,
                memory_content=memory_content,
            )
            + prompt
        )

    # --- Hooks ---
    hooks = _build_hooks(
        agent_name=agent_name,
        restricted_files=restricted_files or {},
        memory_abs_path=memory_abs_path,
        restrict_writes_to_memory=restrict_writes_to_memory,
    )

    # Ensure Write is in allowed_tools if memory is enabled.
    if memory_file and "Write" not in allowed_tools:
        allowed_tools = [*allowed_tools, "Write"]

    options = ClaudeAgentOptions(
        model=model or DEFAULT_MODEL,
        thinking=thinking or DEFAULT_THINKING,
        system_prompt=system_prompt,
        allowed_tools=allowed_tools,
        disallowed_tools=disallowed_tools,
        permission_mode="bypassPermissions",
        max_turns=100,
        cwd=working_dir,
        **({"hooks": hooks} if hooks else {}),
    )

    try:
        result: str | None = None
        async for message in query(prompt=prompt, options=options):
            if isinstance(message, ResultMessage):
                result = message.result
    except CLINotFoundError:
        raise RuntimeError(
            f"{agent_name}: Claude Code CLI not found. "
            "Install with: pip install claude-agent-sdk"
        )
    except CLIConnectionError as exc:
        raise RuntimeError(f"{agent_name}: connection error: {exc}")
    except ProcessError as exc:
        raise RuntimeError(f"{agent_name}: process error: {exc}")

    if not result:
        raise RuntimeError(f"{agent_name} agent produced no output.")

    return result
