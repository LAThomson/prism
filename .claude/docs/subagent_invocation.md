# Sub-Agent Invocation Reference

Sub-agents are invoked as CLI scripts via the Agent SDK. The orchestrator writes a JSON input file, runs the script via Bash, and captures the report from stdout.

## General Pattern

```bash
uv run --with claude-agent-sdk --with python-dotenv python subagents/<agent>/main.py <input.json> [--cwd <dir>]
```

- **Input**: JSON file with agent-specific fields (see below)
- **Output**: Structured markdown report printed to stdout
- **Errors**: Printed to stderr
- **Exit codes**: 0 = success, 1 = input validation error, 2 = agent error

The orchestrator should: (1) write the input JSON to a temp file, (2) run the command via Bash, (3) capture stdout as the report. All agents run fire-and-forget — no back-and-forth.

### Optional: `subagent_model` (all agents)

Every agent's input JSON accepts an optional `subagent_model` field — **the Claude model that the sub-agent itself runs on**. If omitted, the sub-agent uses the scaffold default. Use it to:

- run a sub-agent on a **less refusal-prone model** when an eval's content trips the default model's safety filters (e.g. dangerous-capability evals — the situation that motivated this field); or
- run sub-agents on a **cheaper or weaker model** (e.g. a Sonnet-class model) when the User prefers that cost/quality trade-off.

Do not confuse `subagent_model` with two other model fields:

- the Analyst's **`scanning_model`** — the model Scout uses to run LLM *scanners* (a task parameter), not the model the Analyst agent runs on; and
- the Executor's **`models`** — the eval's *target* models being studied, not the model the Executor agent runs on.

The `subagent_model` is an infrastructure choice; the others are part of the experiment. They are independent and may differ.

## Environment Explorer

**Script**: `subagents/environment_explorer/main.py`

**Input JSON**:
```json
{
    "hypothesis": "Adding X to the system prompt increases Y...",
    "experiment_description": "Testing whether X affects Y...",
    "environment_path": "/absolute/path/to/eval/environment",
    "constraints": "Focus on system prompt and scoring; skip the scaffold directory.",
    "subagent_model": "claude-opus-4-7"
}
```

- `environment_path` must be an existing directory
- `constraints` is optional; free-form string passed through to the Explorer to shape or narrow exploration
- `subagent_model` is optional; the model the Explorer agent runs on (see General Pattern above)

**Returns**: Structured markdown report. See `explorer_interface_contract.md` for the full request and report format.

## Experiment Executor

**Script**: `subagents/experiment_executor/main.py`

**Input JSON**:
```json
{
    "experiment_name": "explicit_goal_framing",
    "experiment_dir": "/absolute/path/to/experiment",
    "conditions": {
        "control": {
            "task": "task.py",
            "args": {}
        },
        "treatment": {
            "task": "task.py",
            "args": {"system": "system_prompt_treatment.txt"}
        }
    },
    "models": ["anthropic/claude-sonnet-4-5-20250929"],
    "overrides": {
        "sample_limit": 50,
        "epochs": 1,
        "skip_preflight": false
    },
    "subagent_model": "claude-opus-4-7"
}
```

- `experiment_dir` must be an existing directory
- `overrides` is optional; supported keys: `sample_limit`, `epochs`, `skip_preflight`, `max_parallel`, `max_connections`, `runs_per_condition`
- `subagent_model` is optional; the model the Executor agent runs on. **Distinct from `models`**, which are the eval's target models — `subagent_model` has no provider prefix (e.g. `claude-opus-4-7`), whereas `models` entries do (e.g. `anthropic/claude-sonnet-4-5-20250929`)

**Returns**: Structured markdown report. See `executor_interface_contract.md` for the full request and report format.

## Transcript Analyst

**Script**: `subagents/transcript_analyst/main.py`

**Input JSON**:
```json
{
    "topic": "How models reason about their operational context and whether they adjust their approach based on perceived circumstances",
    "transcript_source": {
        "condition_A": "/absolute/path/to/logs/run_001",
        "condition_B": "/absolute/path/to/logs/run_002"
    },
    "scanning_model": "openai/gpt-4.1-mini",
    "constraints": {"limit": 100},
    "artefacts_dir": "/absolute/path/to/investigation/artefacts",
    "subagent_model": "claude-opus-4-7"
}
```

- `transcript_source` values must all be existing directories containing `.eval` log files
- `topic` must be a **neutral description** — never the hypothesis
- Use **opaque condition labels** (condition_A, condition_B) — randomise the mapping to conditions
- `scanning_model`, `constraints`, and `artefacts_dir` are optional
- `subagent_model` is optional; the model the Analyst agent runs on. **Distinct from `scanning_model`**, which is the model Scout uses for LLM scanners — `subagent_model` changes which model *does the analysis*, `scanning_model` changes which model the scanners *call*
- When `artefacts_dir` is provided, the analyst writes all file outputs to `<artefacts_dir>/analyst/`

**Returns**: Scanner definitions, validation metrics, quantified results (per-condition detection rates), scan results path, transcript exclusions, transcript excerpts, additional observations. See `analyst_interface_contract.md` for the full report format.
