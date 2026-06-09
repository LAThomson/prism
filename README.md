<img src="docs/prism-icon.png" alt="Prism icon" width="206" align="left">

# Prism: Automating Science-of-Evals Research for AI Safety

**Prism** is a scaffold for automating science-of-evaluations research and model incrimination investigations in [Inspect AI](https://inspect.aisi.org.uk/) evaluations, built on [Claude Code](https://claude.com/product/claude-code), [Inspect Scout](https://meridianlabs-ai.github.io/inspect_scout/) and the [Claude Agent SDK](https://docs.anthropic.com/en/docs/agents/claude-agent-sdk).

Prism ships two skills:

### `/orchestrator` — hypothesis-first investigation

Start here when you have a specific hypothesis about what drives model behaviour and want to test it. Provide a research question; the Orchestrator refines it into a hypothesis with you, then runs an autonomous experiment loop:

1. The *Environment Explorer* identifies minimal, isolated perturbations in the eval;
2. The *Experiment Executor* runs all conditions with preflight validation and error recovery;
3. The *Transcript Analyst* surfaces behavioural patterns behind a hypothesis firewall (it never sees the hypothesis); and
4. The Orchestrator interprets findings, iterates if needed, and delivers a structured report.

### `/investigate` — behavior-first model incrimination

Start here when you have observed concerning behavior and want to determine whether it reflects misalignment. Provide an eval path and a set of scored transcripts; the investigation runs fully autonomously:

1. The *Eval Reader* maps the eval's structure, pipeline, and how to run it;
2. The *CoT Analyst* reads the chain-of-thought to generate competing hypotheses — distinguishing benign causes (confusion, laziness, instruction-following) from malign ones (strategic deception, scheming);
3. The *Experiment Designer* turns the chosen hypothesis into concrete perturbations, proposing both binary and parametric conditions;
4. The *Experiment Executor* runs all conditions;
5. The *CoT Analyst* returns (blinded) to quantify behavioural differences statistically; and
6. The *Reviewer* adversarially checks the conclusions against the model incrimination standard — does the evidence actually establish scheming, or do benign explanations survive?

> **Recommended models.** We observed diminished compliance and less effective use of the scaffold's resources when running these skills on older models (e.g. Opus 4.5). We recommend the most recent Claude models for the best results.

## Prerequisites

- **[Claude Code](https://claude.com/product/claude-code)** — the Orchestrator skill and its sub-agents run inside Claude Code; the scaffold cannot be used without it.
- **API keys** — an `ANTHROPIC_API_KEY` (always required), plus an `OPENAI_API_KEY` if your target eval or its grader uses OpenAI models.

## Quick Start

```bash
# Clone the scaffold and your target eval repo side by side
git clone <this-repo> prism
git clone <your-inspect-ai-eval-repo>
cd <your-inspect-ai-eval-repo>

# Install the scaffold into the target repo. This symlinks the scaffold's
# files in and updates .gitignore. If the target repo has a devcontainer,
# it also patches devcontainer.json to mount the scaffold into the container.
/path/to/prism/install.sh .

# Add your API keys to a `.env` file (loaded automatically by the sub-agents).
# ANTHROPIC_API_KEY is always required; add OPENAI_API_KEY only if your
# target eval or its grader uses OpenAI models.
echo "ANTHROPIC_API_KEY=sk-..." >> .env
echo "OPENAI_API_KEY=sk-..." >> .env  # optional

# Launch Claude Code in the target repo and start an investigation.
#
# Hypothesis-first (you have a research question):
#   /orchestrator [your research question]
#
# Behavior-first (you have transcripts and want to know why):
#   /investigate <path/to/eval> <path/to/transcripts> [research question]

# To uninstall (remove symlinks and revert target repo changes):
# /path/to/prism/uninstall.sh .
```

> **How the scaffold is reached.** The installed symlinks resolve to `/home/inspect/prism`, so the scaffold must be available at that path wherever Claude Code runs. If your target repo uses a devcontainer, `install.sh` wires this up automatically; otherwise (whatever editor or workflow you use) make the scaffold available at that path yourself — e.g. clone or mount it there.

## Directory Structure

```
prism/
├── subagents/
│   ├── runner.py                  # Shared SDK runner + hooks
│   ├── cli.py                     # Shared CLI boilerplate
│   ├── environment_explorer/      # /orchestrator: eval environment analysis
│   ├── experiment_executor/       # Both skills: runs Inspect AI evals
│   ├── transcript_analyst/        # /orchestrator: blinded transcript analysis
│   ├── eval_reader/               # /investigate: eval structure + run instructions
│   ├── cot_analyst/               # /investigate: CoT hypothesis generation + blinded analysis
│   ├── experiment_designer/       # /investigate: binary + parametric perturbation design
│   └── reviewer/                  # /investigate: adversarial model incrimination check
├── .claude/
│   ├── docs/                      # Reference documents and interface contracts
│   ├── skills/orchestrator/       # /orchestrator skill definition
│   ├── skills/investigate/        # /investigate skill definition
│   └── settings.json              # Claude Code permissions
├── scripts/
│   └── execute_evals.py           # Parallel eval execution engine
├── docs/
│   └── scaffold-diagram.png       # Architecture diagram
├── .githooks/                     # Git hooks for scaffold repo
├── install.sh                     # Install into target repo
├── uninstall.sh                   # Remove from target repo
└── README.md
```
