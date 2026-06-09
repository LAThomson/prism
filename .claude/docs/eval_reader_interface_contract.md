# Eval Reader Interface Contract

The Eval Reader produces a structured briefing on an evaluation environment — how it is set up, what it measures, how to run it, and what the scoring logic is. It does not know the hypothesis and does not propose modifications. Its output is used by two downstream agents: the CoT Analyst (call 1, which needs eval context to interpret model reasoning) and the Experiment Designer (which needs the eval structure to propose targeted perturbations).

---

## Request Format

```json
{
    "eval_path": "/absolute/path/to/eval/environment",
    "subagent_model": "claude-opus-4-7"
}
```

- `eval_path`: required. Absolute path to the evaluation environment directory.
- `subagent_model`: optional. Model the Eval Reader agent runs on.

---

## Report Format

The Eval Reader returns a structured markdown report with the following sections.

### Summary

3–5 sentences. What does this eval measure, what does the model do, and what does scoring capture? Include a one-line description of the eval's core mechanic (e.g. "the model is given a coding task and must avoid circumventing a git pre-commit hook") and its scoring logic. This section is the downstream agents' primary orientation — write it so they can proceed without reading the full report.

### Environment Catalogue

For each file in the eval directory:
- Filename and path
- Role in the pipeline (system prompt, user prompt, task configuration, scoring rubric, scaffold, data file, utility script, README)
- Brief description of contents

For large environments, prioritise the prompt → task → scoring path. Explicitly name any files deprioritised.

### Pipeline Model

A step-by-step trace of how the eval flows from input to score:

1. **Prompt construction**: which files contribute to the system and user prompts; what is injected at runtime
2. **Task execution**: what the model is asked to do; what tools or environment it has access to; what a "passing" vs "failing" action looks like
3. **Scoring**: how the model's output is assessed; what metric is reported; what values constitute the concerning behavior
4. **Aggregation**: how per-sample scores combine into eval-level metrics

### How to Run

Exact invocation: the `uv run inspect eval` command with the correct task file path and required `-T` arguments. Include:
- The full command template
- What `-T` parameters the task accepts and what they control
- The log directory convention
- Any required environment variables or setup steps (Docker, API keys, data downloads)
- Any known fragile steps that need care (e.g. "the task fails silently if the Docker daemon is not running")

### Concerning Behavior Description

What is the unsanctioned or concerning action this eval is designed to elicit? Describe it concretely:
- What does the model do when it exhibits the behavior?
- What does the model do when it does not?
- How does the scorer detect the difference?
- What is the baseline rate in the provided transcripts (if transcripts were provided)?

This section is the anchor for downstream hypothesis generation.

### Open Questions

Ambiguities, unclear file roles, or dependencies the investigator should verify before proceeding. Format as a numbered list with a resolution action for each item.
