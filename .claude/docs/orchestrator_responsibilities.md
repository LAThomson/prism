# Orchestrator Responsibilities

This document specifies everything the orchestrator (main Claude Code agent) must do to drive the experimental pipeline. It covers every handoff, every piece of work that falls between sub-agents, and every decision point where the orchestrator must exercise judgment.

## Role

The orchestrator is the only agent that talks to the user, holds the hypothesis, and makes scientific decisions. Think of it as the **principal investigator**: it directs three specialist sub-agents and synthesises their work into findings, but it does not do their work itself. Each sub-agent owns a stage exclusively:

| Agent | Receives | Returns |
|-------|----------|---------|
| Environment Explorer | Hypothesis, experiment description, environment path, optional constraints | Structured briefing: environment summary, pipeline model, modification sites with diffs, variant dependencies, risk assessment, open questions (see `explorer_interface_contract.md`) |
| Experiment Executor | Experiment name, directory, condition specs, models, optional overrides | Structured execution report: summary, preflight exclusions, execution matrix, error summary, transcript termination metadata, concurrency decision, execution summary, additional notes (see `executor_interface_contract.md`) |
| Transcript Analyst | Topic (not hypothesis), transcript source (condition→path mapping), scanning model?, constraints? | Scanner definitions, validation metrics, quantified results, scan results path, transcript exclusions, excerpts |

The orchestrator does everything that falls *between* these delegated stages — refining the hypothesis, designing conditions, applying environment modifications, interpreting the Analyst's findings, deciding the next step, and reporting to the user. What it must never do is take over a sub-agent's stage: it never runs evals itself (the Executor's job), never takes over the Explorer's systematic exploration of the eval to design perturbations (though it may read the eval to orient itself and form hypotheses), and never reads transcripts to surface behavioural patterns itself (the Analyst's job). Bypassing a sub-agent forfeits the scaffold's integrity guarantees — see the Anti-Patterns. The one exception is genuine sub-agent failure, handled explicitly in the Sub-Agent Failure Handling section below.

## Pipeline Overview

```
Phase 1: Scoping Discussion (with user)
    ↓
Phase 2: Investigation Loop (autonomous, may repeat)
    ├── 2a. Launch Environment Explorer
    ├── 2b. Review Explorer report and decide on conditions
    ├── 2c. Create experiment directory and apply modifications
    ├── 2d. Construct Executor input and launch Executor
    ├── 2e. Review Executor report and handle failures
    ├── 2f. Translate hypothesis → neutral topic
    ├── 2g. Launch Transcript Analyst
    ├── 2h. Sanity-check Analyst report
    ├── 2i. Interpret Analyst findings against hypothesis
    └── 2j. Decide: iterate, conclude, or escalate to user
    ↓
Phase 3: Report to User
```

---

## Phase 1: Scoping Discussion

### What happens

The user presents a research question. The orchestrator helps articulate it as the durable scope of the investigation and refine an initial testable hypothesis that addresses it, then gathers the information needed to begin.

### Orchestrator responsibilities

1. **Articulate the research question and an initial testable hypothesis.** Two outputs from this step:
   - *Research question*: a one-paragraph statement of what is being investigated. This is the durable framing the investigation will be judged against — broad enough to survive across iterations, narrow enough to constrain what counts as in-scope work. It becomes the *Research question* bullet of the Agreed Scope.
   - *Initial hypothesis*: a specific, testable hypothesis to investigate in iteration 1. A good hypothesis names a specific independent variable (what changes between conditions), a dependent variable (what is measured), and a direction (what the expected effect is). A vague question like "does the system prompt matter?" is not yet a hypothesis. The investigation may generate further hypotheses in subsequent iterations as evidence accumulates; the research question stays put.

   **Methodological checks** (see `eval_science_principles.md`):
   - *Falsifiability*: Can you state what outcome would make this hypothesis wrong? If not, it is not ready to test.
   - *Competing hypotheses*: What alternative explanations exist for the predicted outcome? A good investigation cycle eliminates at least one alternative, not just accumulates evidence for the favoured hypothesis.
   - *Eval awareness*: If this is an alignment or safety evaluation, flag evaluation awareness as a default competing hypothesis. The observed behaviour may be driven by the model detecting the evaluation context rather than by the manipulated variable.

2. **Identify the eval environment.** Determine the path to the evaluation environment that will be used. Confirm it exists and contains task files.

   **Methodological check** (see `eval_science_principles.md`):
   - *Five validity questions*: (1) What construct does this evaluation claim to measure? (2) Do the items actually test for it? (3) Does the setting resemble real deployment? (4) Would a different evaluation of the same construct agree? (5) Could it be measuring something else entirely? Document the answers — validity gaps are themselves findings about the evaluation.

3. **Determine models.** Agree with the user on which model(s) to evaluate. Record the exact `provider/model-name` strings.

   **Methodological check** (see `eval_science_principles.md` §3, Q4 corollary): When proposing or accepting a single-provider model set, name the construct-validity implication explicitly to the user — findings about a *construct* obtained on one provider's models test one operationalisation, not the construct itself. If the research question is about the construct rather than about a specific provider or model, surface a multi-provider option, alongside its practical preconditions: commercial alternatives (e.g. OpenAI, Google) require additional API keys in the project's `.env` file before step 4; open-weight models (e.g. from HuggingFace) can be run locally given GPU resources, removing the API-key dependency but adding setup overhead. The user's choice stands either way — single-provider, and indeed single-model, is a legitimate scope decision when the question is about that specific provider or model (e.g. *"how does Opus 4.7 behave under condition X?"*), when compute or refusal-rate constraints rule out alternatives (as in dangerous-capability evals), or when the user explicitly accepts the construct-validity limitation for a construct-level claim. The discipline is in raising the question, not in forcing the answer.

4. **Verify API key availability.** Based on the chosen models, determine which API keys are needed (e.g., `ANTHROPIC_API_KEY` for Anthropic models, `OPENAI_API_KEY` for OpenAI models). Check that a `.env` file exists in the project root (`test -f .env`). If it does not exist, ask the user to create one with the required keys before proceeding. Do **not** attempt to verify key values, print environment variables, or export keys in the session — keys are loaded automatically by the subagent launcher and must never appear in transcripts.

5. **Set execution parameters.** Discuss with the user:
   - Sample limit (full dataset or a subset for rapid iteration?)
   - Number of epochs per sample
   - Whether to skip preflight validation
   - Parallelism preferences (`max_parallel` — how many eval runs to execute concurrently; if unset, the Executor decides based on environment assessment)
   - Any other Inspect CLI overrides

6. **Agree on cost parameters.** Discuss with the user:
   - *Total API budget*: What is the rough ceiling the user is comfortable spending on this investigation? This anchors all downstream cost decisions.
   - *Run strategy*: Does the user prefer fewer large-N runs (more statistical power per iteration, higher confidence) or more small-N exploratory runs (broader coverage of hypotheses, less confidence per result)? This choice shapes sample limits and iteration count.
   - *Baseline drift policy*: If control conditions produce substantially different results across iterations, should the orchestrator re-run controls to check reproducibility (costs an extra iteration's compute) or flag the inconsistency and continue? Small sample sizes make some drift expected — agree on how much warrants action.
   - *Iteration cap*: Maximum number of investigation loop cycles before stopping, regardless of whether findings are conclusive. This prevents runaway costs on ambiguous questions.

7. **Initialize the investigation directory.** Create `investigations/<investigation_name>/` at the workspace root, where `<investigation_name>` is a snake_case identifier for the research question (e.g., `agentic_misalignment_blind_spots`). All Orchestrator outputs for this investigation live here. Inside it, create `INVESTIGATION-LOG.md` to track state across iterations (see State Management below). The final `FINDINGS-REPORT.md` will be written here as a sibling at the end of the investigation (see Phase 3). The log's `## Agreed Scope` section (filled in by the end of Phase 1) is the load-bearing reference for downstream tactical/strategic categorisation at Phase 2j — write it explicitly enough that out-of-scope decisions can be detected later by comparing a proposed action against it.

### What can go wrong

- The user's hypothesis is too vague or tests multiple variables simultaneously. Push for specificity.
- The eval environment path doesn't exist or is empty. Verify before proceeding.
- The user wants to test a model the orchestrator doesn't have API access to. Verify model accessibility early (or let the Executor's preflight catch it).

---

## Phase 2: Investigation Loop

### Step 2a: Launch Environment Explorer

**Launch the Explorer at the start of each iteration rather than mapping the environment yourself.** You will and should read enough of the eval to form relevant hypotheses — especially during Phase 1 scoping, where the eval may be mid-development with no README or documentation, and a direct look at the task files is the only way to ground the research question. That orientation reading is legitimate and often necessary. What belongs to the Explorer is the *systematic* exploration that produces the modification briefing: enumerating minimal perturbation sites with concrete diffs, mapping variant dependencies, and assessing risk. Don't substitute your own ad-hoc site-hunting for that briefing, and don't skip the Explorer because you've already glanced at the files. Task it, then act on what it returns.

The request and report formats for the Explorer are defined in `explorer_interface_contract.md`. That document is the single source of truth; consult it for field-level and section-level detail.

**Orchestrator work:**
- **Precondition: write the `### Hypothesis this iteration` block before launching the Explorer.** The iteration's hypothesis must be named in the investigation log's per-iteration *Hypothesis this iteration → Statement* field before the Explorer is invoked, and the hypothesis string passed to the Explorer must match the Statement field exactly. If you find yourself about to pass a different hypothesis to the Explorer than what the block says, stop and update the block first — silent mismatches between log and Explorer input are the same failure mode as silent hypothesis swaps between iterations (see Anti-Patterns).
- Construct the Explorer input JSON per `explorer_interface_contract.md §Request Format` and launch via CLI script (see `subagent_invocation.md`).
- The hypothesis IS passed to the Explorer — this is the one agent that receives it directly. (The Transcript Analyst must NOT receive it.)
- If prior iterations have narrowed the scope, pass any shaping preferences via the optional `constraints` field (e.g., "focus on system prompt and scoring; skip the scaffold directory").
- Save the Explorer's stdout report to `<iteration_dir>/artefacts/explorer/report.md`.

**What can go wrong:**
- The Explorer reports that no viable modification sites exist with the given environment and hypothesis. Report to user and revise.
- The Explorer reports that the environment path is empty or unreadable. Check the path and retry.

---

### Step 2b: Review Explorer Report

The report structure is defined in `explorer_interface_contract.md §Report Format`. The orchestrator should read the Explorer's report end-to-end before proceeding; the Summary section flags global Blockers early, but the full report carries the reasoning the orchestrator needs for condition construction.

**Interpreting the Explorer's report:**

1. **Attend to Blocker flags first.** A **Blocker** flag in the Explorer's report means "this would invalidate the experiment." Scope determines response:
   - *Global Blocker* (in the Global Risk Assessment section) — no condition under this design is viable. Redesign the manipulation or revise the hypothesis before proceeding.
   - *Per-site or per-variant Blocker* — that specific variant is unusable. Other variants at the same site may be fine.
   - *Per-condition Blocker* — that specific condition is unusable, others may still be runnable.

   The Explorer errs toward over-flagging (as specified by the contract's asymmetric error preference). Treat each Blocker as a serious candidate for design change, but check it against the full diff and the Pipeline Model before acting.

2. **Resolve the Uncertainty & Open Questions section before proceeding.** Each item names what the orchestrator needs to do to resolve it (read a specific file, ask the user, run a cheap sanity check). Unresolved items can silently confound the experiment; do not apply modifications in Step 2c while open questions remain.

3. **Use the Pipeline Model to sanity-check proposed sites.** For each modification site the Explorer proposed, confirm from the Pipeline Model that the site actually lies on the path affecting the hypothesised variable. If the Pipeline Model and a proposed site disagree — for example, the site is in a file the Pipeline Model describes as peripheral — the Explorer's reasoning is probably incoherent; flag the discrepancy rather than proceeding.

4. **Construct conditions from the Explorer's raw material.** The Explorer reports modification sites, variants at each site, and (if applicable) Variant Dependencies. It does not recommend which conditions to run. The orchestrator constructs conditions by:
   - Choosing a variant at each relevant site. Discard any variant carrying a Blocker flag.
   - Respecting Variant Dependencies — if the Explorer recorded that Variant A at Site 1 requires Variant B at Site 2, do not construct a condition that pairs them otherwise.
   - Naming each condition in filesystem-safe `snake_case` (e.g., `control`, `treatment_explicit_goal`).
   - Deciding factorial vs. selected design: if the hypothesis concerns a single IV, control + treatment at the relevant site(s) suffices. If the hypothesis concerns an interaction between multiple IVs, run all coherent combinations of variants. Cost and iteration-budget constraints may require pruning; prune by scientific relevance, not by convenience.

**Additional methodological checks:**

5. **Check for dirty paraphrases** (see `eval_science_principles.md`). Review each proposed diff and ask: does this modification change only the intended variable, or does it simultaneously alter formatting, length, style, or other incidental properties? Any modification to an evaluation simultaneously modifies its formatting properties. If the diff changes more than one thing, consider whether a cleaner manipulation exists or whether a placebo condition (same magnitude of change, orthogonal content) is needed to distinguish content effects from perturbation effects. The Explorer should have flagged this per-site, but verify independently.

6. **Review cross-file interactions.** The Explorer reports cross-file dependencies within modification sites and as Variant Dependencies. Plan to apply all coordinated changes together. Missing one could introduce confounds or break the eval.

7. **Consider evaluation item quality** (see `eval_science_principles.md`). Before attributing model behaviour to the construct under study, check whether the evaluation items are well-formed. Roughly 9% of items in well-known benchmarks contain errors. If the Explorer flagged scoring or task validity concerns, factor these into the experimental design — they may explain more of the variance than the intended manipulation.

**What can go wrong:**
- The Explorer's proposed diffs are ambiguous or reference files that have changed since it read them. Re-read the files and verify the diffs still apply.
- The Explorer's variants and the Pipeline Model are inconsistent (e.g., a modification site is proposed in a file the Pipeline Model treats as peripheral). Investigate rather than proceeding.
- Too many unresolved items in Uncertainty & Open Questions to proceed confidently. Resolve them or escalate to the user before Step 2c.

---

### Step 2c: Create Experiment Directory and Apply Modifications

This is entirely the orchestrator's work. No sub-agent handles this.

**Methodological check** (see `eval_science_principles.md`): Evaluation flaws should be characterised, not fixed. Do not clean up the evaluation environment before studying it — that changes the object of study. If you notice flaws (ambiguous items, broken scoring, unrealistic scenarios), document them as potential confounds but leave them in place. The flaw itself may be driving the behavioural variation, and that discovery is a contribution.

**Orchestrator work:**

1. **Create the iteration directory.** Each iteration gets its own isolated working copy of the eval environment under the investigation directory. Convention:
   ```
   investigations/<investigation_name>/<iteration_name>/
   ```
   where `<iteration_name>` is a descriptive snake_case identifier for this iteration (e.g., `explicit_goal_framing_v1`).

   **Each iteration directory is immutable once created.** When starting iteration N+1, create a new sibling directory rather than editing iteration N. Two cases:
   - *Fresh perturbation:* copy the original eval environment into the new iteration directory. This preserves the original for future iterations.
   - *Extending a previous perturbation:* copy iteration N's modified eval into iteration N+1's new directory as the starting point, then apply the new diffs there. Iteration N's directory must remain unchanged — it is evidence.

   Previous iteration directories are never modified — not to clean up artefacts, not to fix typos, not to apply a "small additional" perturbation. They are the reproducible record of what was actually run, and the investigation's scientific value depends on preserving them as-is. This is restated as Anti-Pattern #2 below.

   **Create an artefacts directory** within the iteration directory:
   ```
   investigations/<investigation_name>/<iteration_name>/artefacts/
   ```
   This directory is passed to sub-agents that produce file outputs. Each sub-agent creates its own subdirectory (e.g., `artefacts/analyst/`). The orchestrator saves stdout reports from sub-agents that cannot write files themselves (the Environment Explorer) to `artefacts/explorer/report.md`.

2. **Apply the Explorer's diffs and choose the activation pattern.** The Explorer provides diffs with exact file paths and line ranges but does not prescribe how conditions are activated at runtime — that is Inspect-specific translation the orchestrator handles here. Choose one of the following patterns based on the diffs:
   - **Parameter-based conditions** (Pattern A): apply any shared modifications common to all conditions, then rely on different `-T` values to activate each condition at runtime. This may involve creating condition-specific copies of files referenced by the parameter (e.g., `system_prompt_control.txt`, `system_prompt_treatment.txt`).
   - **Separate task files** (Pattern B): create a copy of the task file for each condition, applying the relevant diffs to each copy. Name them with the condition name (e.g., `task_control.py`, `task_treatment.py`).
   - **Model variation only** (Pattern C): no file modifications needed beyond any shared setup.

3. **Verify the modifications.** Read each modified file back and confirm the changes match the Explorer's diffs. This catches copy/paste errors and merge conflicts.

4. **Handle cross-file dependencies.** Apply all coordinated changes flagged by the Explorer. If the Explorer said "changing the system prompt at Site 1 requires updating the scoring rubric at Site 2," both must be applied.

**What can go wrong:**
- The Explorer's diffs don't apply cleanly (e.g., the "before" text doesn't match what's in the file because of whitespace or encoding differences). Manually inspect and adapt.
- The experiment directory copy fails because of large data files or symlinks. Use the appropriate copy strategy (e.g., symlink data files rather than copying them).
- For iteration 2+, the orchestrator accidentally modifies the previous iteration's directory. Always create a new directory.

---

### Step 2d: Construct Executor Input and Launch Executor

**Every eval runs through the Executor. You never invoke `uv run inspect eval` (or any `inspect eval`) yourself** — not to "quickly check" a condition, not when only one condition needs running, not when the Executor is slow. Running an eval directly bypasses the Executor's preflight, error taxonomy, and reporting, and puts raw scores in front of you in violation of the firewall (Step 2e).

The request and report formats for the Executor are defined in `executor_interface_contract.md`. That document is the single source of truth; consult it for field-level and section-level detail.

**Orchestrator work:**

1. **Build the condition specification.** From the conditions constructed in Step 2b and the activation pattern chosen in Step 2c, assemble a mapping for each condition per `executor_interface_contract.md §Conditions`:
   - Condition name (`snake_case`)
   - Task file path (relative to `experiment_dir`)
   - Task arguments (`-T key=value` pairs that differ between conditions)

2. **Assemble the Executor input JSON** per `executor_interface_contract.md §Request Format`. Required: `experiment_name`, `experiment_dir`, `conditions`, `models`. Pass this iteration's `<iteration_name>` and `<iteration_dir>` as the values of the schema's `experiment_name` and `experiment_dir` fields respectively — the schema retains its historical field names but the values are per-iteration. Optional `overrides` supports `sample_limit`, `epochs`, `skip_preflight`, `max_parallel`, `max_connections`, `runs_per_condition`.

3. **Launch the Experiment Executor sub-agent** via CLI script (see `subagent_invocation.md`).

4. **Save the Executor's stdout report** to `<iteration_dir>/artefacts/executor/report.md`.

**What can go wrong:**
- A task file path in `conditions` does not resolve inside the experiment directory. Double-check paths before launching.
- Execution parameters agreed with the user in Phase 1 are missing from `overrides`. Refer to the investigation log.
- `-T` argument values are the wrong type for the task's signature (e.g., strings where numbers are expected). The Executor's preflight will catch these, but you can save an iteration by checking against the task file first.

---

### Step 2e: Review Executor Report

The report structure is defined in `executor_interface_contract.md §Report Format`. Read the Summary first — 3–5 sentences naming the final disposition of every condition-model pair and flagging the most decision-critical observation. The remaining sections provide drill-down.

**Do not read eval results.** Between receiving the Executor's report and receiving the Analyst's report, do not read eval log file contents, extract scores, compute aggregate metrics, or run `inspect log list/dump` on experiment log directories. The Executor's report contains everything needed to decide whether to proceed: Execution Matrix status, Error Summary categories and evidence, and Transcript Termination Metadata. You may verify that log *files exist* (e.g., `ls` the log directory to confirm paths before passing them to the Analyst), but you must not read their *contents*. The Analyst's blinded report must be your first view of the experimental results. Reading scores early contaminates your interpretation of the Analyst's findings — you will unconsciously seek confirmation of what you already know.

**Interpreting the Executor's report:**

1. **Read Preflight Exclusions before the Execution Matrix.** Excluded pairs never reached full execution, so their absence from the Matrix is not a bug but a gate. For each exclusion:
   - *Reason*: `structural` means the eval could not run at all; `all-samples-deterministic-sample-error` means the `--limit 3` retest found persistent sample failures and proceeding would waste compute.
   - *Evidence*: structural exclusions ship exit code, command, and stderr tail. Read the stderr to diagnose whether the cause is (i) a bug in the modifications applied in Step 2c, (ii) a missing infrastructure prerequisite (API key, Docker daemon, task file), or (iii) an Inspect-side issue.
   - *Asymmetric exclusions*: if all excluded pairs are in the same condition (e.g., every `treatment` pair excluded while every `control` pair runs), this is a strong signal that Step 2c broke the eval for that condition. Re-apply the Explorer's diffs, verify them against the Pipeline Model, and re-run.

2. **Read the Execution Matrix for the pairs that ran.** Scan the `Status` column for anything other than `success`. The `Sample-Level Retries` column flags pairs where `--retry-on-error` fired; non-zero retries introduce distribution-shift concerns (see item 7 below).

3. **Interpret the Error Summary by category.** Each category gates a different action:
   - **Transient (recovered)**: informational. The eval completed; proceed.
   - **Sample-level**: the eval completed but some samples errored. The Analyst will quantify per-condition attrition. Proceed, but record the attrition for the Analyst's delegation brief.
   - **Structural**: the eval did not run to completion. Do not proceed without investigation. Read the evidence (exit code, command, stderr) to diagnose. Common signatures:
     - `ImportError` referencing a file you created in Step 2c → your modification introduced a bug; re-check the diff rather than re-running.
     - `Authentication` / `401` / `API key` in stderr → verify `.env`; do not print key values.
     - `Docker` / `sandbox` errors → sandbox infrastructure; may need `inspect sandbox cleanup docker`.
     - `No such file` referencing a task file → Step 2d path was wrong.

4. **Handle partial failures.** If some pairs failed but not all:
   - *Symmetric failures* (similar rates across conditions) — data may still be usable; note for the Analyst's delegation brief.
   - *Asymmetric failures* (one condition failed more than another) — this is a confound. Consider re-running the failed pairs, investigating whether the treatment modifications broke the eval, or reporting the asymmetry to the user. Do not silently proceed.

5. **Handle total failure.** If the Execution Matrix has no successful pairs (after accounting for Preflight Exclusions), do not launch the Analyst. Diagnose from the evidence, fix if possible, and re-run. If the problem is unfixable, escalate to the user.

6. **Read Transcript Termination Metadata.** Per-pair counts of transcripts with no assistant messages, limit hits, and error terminations. Before delegating to the Analyst:
   - If a condition has many empty (no-assistant-msg) transcripts, the Analyst will have little behavioural signal to scan. Note this as a limitation in the delegation brief.
   - If limit hits or error terminations differ markedly between conditions, this is a form of differential attrition — flag it as a potential confound.
   - These counts describe transcript *shape*, not *quality*. A transcript with assistant messages, no limit hit, and no termination error is unremarkable here regardless of whether its content looks strange — content judgement is the Analyst's job.

7. **Communicate retry flags and attrition to the Analyst.** Sample-Level Retries and sample-level errors represent populations the Analyst must reason about. When you construct the Analyst's request in Step 2g:
   - Include per-condition sample-level retry counts and sample-error counts as a caveat.
   - Note that retried samples may exhibit distribution shift relative to non-retried ones (the retry succeeded conditional on a prior failure, which can introduce selection effects).

8. **Audit the Concurrency Decision.** The structured fields let you verify the Executor's choice was reasonable. If `Reductions applied during execution` is non-empty, the initial concurrency estimate was wrong and some re-runs occurred. This is not a failure but is worth noting if wall-clock matters for the investigation.

9. **Record in investigation log.** Update the investigation log with: condition-model pairs completed / failed / excluded, key errors, retry counts, transcript termination patterns, and chosen concurrency.

**Common pitfalls:**

- **Re-running a structural failure without fixing its cause.** If the stderr shows an ImportError from your Step 2c modifications, re-running will not help. Fix the modification first.
- **Treating sample-level errors as transient.** Sample-level errors represent real attrition. They do not disappear on re-run unless the underlying cause is genuinely transient (which is usually caught at the process level and classified as Transient by the Executor already).
- **Ignoring asymmetric preflight exclusions.** Symmetric exclusions across conditions suggest an infrastructure problem. Asymmetric exclusions almost always mean Step 2c broke something for a specific condition — re-applying the diffs is usually the fix.
- **Proceeding to the Analyst without forwarding attrition.** The Analyst cannot detect differential attrition from transcripts alone; you must pass the per-condition counts forward.

**What can go wrong:**

- The Executor's report is ambiguous about whether a failure is structural or transient. Re-read the evidence rather than asking the Executor for clarification — delegations are single-shot, and re-invoking is more expensive than careful reading.
- Log paths in the Matrix do not exist (Executor bug). Verify log paths exist before passing them to the Analyst.
- A condition-model pair present in the request is missing from both the Matrix and Preflight Exclusions. This violates the contract's accountability requirement; escalate rather than silently proceeding.

---

### Step 2f: Translate Hypothesis to Neutral Topic

This is the orchestrator's most important cognitive task. The Transcript Analyst must never receive the hypothesis. It receives only a neutral topic.

**Translation rules:**

1. **Strip directionality.** Remove words like "increases," "decreases," "improves," "reduces," "more," "less."
2. **Strip mechanism claims.** Remove "because," "due to," "by causing," "leads to."
3. **Keep the domain.** The topic should cover the same behavioral space as the hypothesis.
4. **Keep it open-ended.** The topic should allow the Analyst to find patterns in either direction (or no direction).
5. **Don't smuggle the hypothesis.** Avoid loaded language that implies an expected direction.

**Examples:**

| Hypothesis | BAD Topic | GOOD Topic |
|------------|-----------|------------|
| "Explicit goal framing increases deceptive behavior" | "Whether explicit goals cause deception" | "How the model reasons about and frames its goals across conditions" |
| "Chain-of-thought prompting improves accuracy on reasoning tasks" | "Whether CoT helps with reasoning" | "Differences in response structure and problem-solving approach across conditions" |
| "System prompt persona framing increases refusal rates" | "How persona affects refusals" | "Response patterns and refusal behaviour across conditions" |
| "Models are more sycophantic when told the user is an expert" | "Sycophancy toward experts" | "How the model adjusts its communication style based on user context" |
| "Models avoid shutdown when warned about task termination" | "Events that may affect task completion" | "Model behavior during task interruptions" |

**Watch for consequence framing.** The examples above mostly show obvious failures — directly naming the hypothesis construct. The subtler failure mode is a topic that passes all five rules but frames the analyst's search in terms of *effects on outcomes* rather than *regions of behavior*. "Events that may affect task completion" contains no directionality, no mechanism claims, and seems open-ended — but "affect task completion" tells the analyst to look for things that *change outcomes*, which narrows scanner design toward consequential behaviors. Compare with "model behavior during task interruptions," which points to the same region of the transcript without implying the analyst should be measuring effects. A good neutral topic says *where to look*, not *what kind of relationship to look for*.

**Self-check:** After writing the topic, ask: "If I read only this topic and knew nothing about the hypothesis, would I be biased toward finding any particular pattern?" If yes, revise.

---

### Step 2g: Launch Transcript Analyst

**Orchestrator work:**

1. **Construct the request** following the format in `analyst_interface_contract.md`:
   - **Topic**: The neutral topic from Step 2f.
   - **Transcript source**: A mapping from opaque condition labels to log directory paths (e.g., `{"condition_A": "<iteration_dir>/logs/control/", "condition_B": "<iteration_dir>/logs/treatment/"}`). Randomise the mapping between condition labels and actual conditions.
   - **Scanning model** (optional): Override the default scanning model if needed.
   - **Constraints** (optional): Limit transcript count, concurrency, etc.
   - **Artefacts directory**: Pass `<iteration_dir>/artefacts/` so the analyst writes its outputs to `<iteration_dir>/artefacts/analyst/`.

2. **Launch the Transcript Analyst sub-agent** via CLI script (see `subagent_invocation.md`).

3. **After the Analyst returns**, review the scan results path provided in the report for sanity-checking summary statistics.

**What can go wrong:**
- The log directories contain no `.eval` files (e.g., the Executor put logs in a different location than reported). Verify the paths contain logs before launching.
- The condition labels leak the experimental design (e.g., using "control" and "treatment" instead of opaque labels). Always use condition_A, condition_B, etc.
- The topic accidentally contains hypothesis-leaking language. Re-read the topic one more time before launching. See `analyst_delegation_guide.md` for detailed guidance.

---

### Step 2h: Sanity-Check Analyst Report

**What the orchestrator receives** (see `analyst_interface_contract.md` for full format):
- Scanner definitions (names, types, questions/patterns)
- Validation metrics — chance-adjusted agreement (κ), precision, recall, F1, validation set size, labelling method, validator-model identity per scanner
- Quantified results — per-condition rates with scanner-adjusted bounds and Wilson CIs; between-condition rate-difference Newcombe-Wilson CIs and Fisher's exact p-values; multiple-comparisons count and Bonferroni-corrected p-values when applicable; "Provisional" subsection for unvalidated scanners
- Scan results path (for sanity-checking summary statistics)
- Transcript exclusions (counts and reasons, by condition)
- Transcript excerpts (illustrative message references)
- Additional observations

**Orchestrator work:**

Run lightweight consistency checks before interpreting findings. See `analyst_delegation_guide.md` for detailed guidance.

1. **Verify summary statistics.** Do per-condition counts sum to the total? Are reported rates arithmetically consistent with the raw counts?

2. **Check validation reliability per scanner — hard gate.** Each headline scanner in the Summary must show κ ≥ 0.4 AND precision ≥ 0.6. If a scanner in the Summary fails either threshold, the analyst violated the contract — treat that scanner's findings as provisional regardless of its placement and note the contract breach in the investigation log. If the report includes a *same-family-agreement risk* flag, the analyst has already downgraded the affected scanner; honour the downgrade.

3. **Check the between-condition CIs against zero — the headline falsifier.** For each headline finding, look at the Newcombe-Wilson CI on the rate difference. If it straddles zero, the finding is a null result regardless of how large the per-condition rate gap appears — report it as such in §2i and Phase 3. Do not selectively cite the per-condition rates when the CI on the difference is uninformative.

4. **Check for floor/ceiling exposure on apparent nulls — hard gate.** Per-condition rates are tagged `[floor]` (upper Wilson CI < 0.20) or `[ceiling]` (lower Wilson CI > 0.80) in the analyst's report. A between-condition null where one or both conditions carry such a tag is **not** evidence of construct equivalence — it is evidence the elicitation regime has no headroom to register the effect under that condition. Degrade any such finding to *uninformative-due-to-floor/ceiling* in §2i and Phase 3. Treat the next-iteration decision (§2j) as a metric / manipulation-strength / elicitation-regime question, not a hypothesis question — there is no point varying H when the metric cannot move. Floor/ceiling exposure also applies to between-condition differences that *do* clear the CI gate: a 90% → 70% drop and a 30% → 10% drop are both 20pp, but the headroom asymmetry shapes the interpretation, so surface the markers in §2i either way.

5. **Engage with the multiple-comparisons count.** If the analyst reports > 5 between-condition tests across all scanners and pairs, read the Bonferroni-corrected p-values. Any "would not survive multiplicity correction" flag means the finding is hypothesis-generating, not evidence — degrade your interpretation accordingly. Persistent failure to survive Bonferroni across iterations is itself a signal that the investigation is generating noise rather than findings.

6. **Check the reliability flag per Summary scanner.** Scanners tagged `marginal` (0.4 ≤ κ < 0.6) should not anchor your interpretation in §2i; treat them as supporting context for `reliable` findings (κ ≥ 0.6), not as headline evidence in their own right.

7. **Check for differential attrition.** Are transcript exclusion counts balanced across conditions?

---

### Step 2i: Interpret Analyst Findings

**Orchestrator work:**

1. **Read the full report.** Do not skim. The Analyst's report is structured to prevent cherry-picking — outliers and limitations are given equal weight.

2. **State the null hypothesis and simplest alternative before interpreting** (see `eval_science_principles.md`). What would you expect if the manipulated variable had no effect? What would you expect if the observed effect were due to a confound (e.g., formatting differences, eval awareness) rather than the intended manipulation? Write these down in the investigation log before reading the Analyst's quantified results. This prevents post-hoc rationalisation.

3. **Map patterns to the hypothesis.** For each pattern the Analyst observed, consider:
   - Does this pattern relate to the hypothesis? (Some patterns may be interesting but irrelevant.)
   - Does it support the hypothesis, contradict it, or is it ambiguous?
   - How strong is the evidence? (How many transcripts? What percentage?)

4. **Check for unexpected findings.** The Analyst may have found patterns the orchestrator didn't anticipate. These are valuable — they may suggest alternative hypotheses or confounds.

5. **Use mechanistic language** (see `eval_science_principles.md`). Describe what models produced under what conditions. Do not attribute intent or knowledge ("the model recognised it was being tested"). Mentalistic language is a conclusion that requires systematic exclusion of simpler explanations — it is almost never warranted at this stage.

6. **Quantified patterns are evidence; individual transcripts are anecdotes.** The Analyst provides transcript excerpts for context, but no conclusion should rest on an individual excerpt. Cite detection rates and validation metrics, not striking examples.

7. **Consider the limitations.** If the Analyst flagged sampling limitations, ambiguous cases, or insufficient evidence, factor this into interpretation.

8. **Consider the Executor's retry flags.** If retried samples exist, the Analyst's patterns might be influenced by distribution shift. Note this caveat.

9. **Record in investigation log.** Update with key findings, interpretation, and any new questions raised.

---

### Step 2j: Decide Next Action

**Step 0: Classify and select among candidate actions.**

Before reviewing the options below, generate the candidate actions you are seriously considering for the next iteration. **Begin by reviewing prior iterations' *Runner-up candidates carried forward* lists** — these are the alternatives you previously deemed worth revisiting; consider each alongside fresh candidates suggested by this iteration's findings and *Surprises*. If a prior runner-up is no longer worth pursuing (e.g. already addressed by another iteration's findings), note why it's being retired in this iteration's *Decision* reasoning rather than silently dropping it. For each surviving candidate (whether carried-forward or fresh), perform two operations:

1. **Classify** as in-scope (tactical) or out-of-scope (strategic) relative to the Phase 1 Agreed Scope. An action is in-scope if it lies within the Agreed Scope — investigates a hypothesis that addresses the agreed research question, uses agreed models on the agreed eval environment, stays within the iteration cap and cost budget. It is out-of-scope if it would require any of: changing the research question, investigating a hypothesis the research question does not cover, adding models outside the agreed set, changing the eval environment, exceeding the iteration cap or cost budget, or changing the object of study (eval-as-object ↔ behaviour-as-object).
2. **Rank** all candidates by expected information value using the *Evaluate hypothesis quality* rubric below (information value, mechanism plausibility, marginal contribution, competing use of resources).

Then apply the selection rule:

- If the top-ranked candidate is **in-scope**: proceed per the autonomy agreement.
- If the top-ranked candidate is **out-of-scope**: consult the user. Present the strategic candidate and the best in-scope alternative(s), with your reasoning for why strategic looks more informative. The user decides whether to expand scope (renegotiation is allowed at any time during the investigation) or stay in scope.

**Why this routing:** The cost of consulting the user has already been calibrated at scope-setting time. A user who specified a narrow scope signalled *"interrupt me on anything significant"*; a user who specified a broad scope signalled *"you have leash."* The scope IS the cost-of-consultation dial; the Orchestrator does not re-weigh that dial per iteration. Strategic candidates are not artificially suppressed; they go through the consultation channel rather than the autonomous one.

If this iteration's *Surprises* entry flagged *"this suggests a move outside the agreed scope"* (final prompt of the per-iteration log), Step 0 is where that flag is operationalised: the candidate action implied by the surprise is the out-of-scope candidate to surface for consultation.

Indicative classification examples (scope-dependent; not exhaustive):

| Action type | Typically |
|---|---|
| Same hypothesis, additional conditions for a confound the scope anticipates | Tactical |
| Same hypothesis, different parameters within the cost budget | Tactical |
| Different model within the agreed set | Tactical |
| Pivot to a hypothesis explicitly within an agreed survey scope | Tactical |
| Pivot to a different hypothesis (narrow scope) | Strategic |
| Change the object of study (eval-as-object ↔ behaviour-as-object) | Strategic |
| Add models outside the agreed set | Strategic |
| Exceed the agreed iteration cap or budget | Strategic |
| Investigate a confound that requires fundamentally different conditions | Strategic |

When in doubt, default to consulting (existing principle).

**Options:**

1. **Conclude.** The findings are clear enough to report. Proceed to Phase 3.

2. **Iterate with refined hypothesis.** The findings suggest a more specific or different hypothesis worth testing. Go back to Step 2a with a new hypothesis, potentially using the same eval environment. *Writing the next iteration's `### Hypothesis this iteration` block in the investigation log is part of choosing this option, not documentation for later — the new hypothesis must be named in the Statement field before the next Explorer launch.*

3. **Iterate with different execution parameters.** The findings are promising but the sample size was too small, or more epochs are needed. Go back to Step 2d with different parameters (same conditions, same modifications).

4. **Iterate with additional conditions.** The findings suggest a confound or an unexplored variable. Go back to Step 2a asking the Explorer to identify additional modification sites or variants relevant to the new angle, then construct conditions from its raw material per Step 2b.

5. **Escalate to user.** The findings are ambiguous, the orchestrator is unsure how to proceed, or the investigation has reached the limits of what's useful without human judgment. Present what's been found and ask for direction.

**Respect the autonomy agreement.** Before deciding to iterate, check the autonomy agreement from Phase 1. If the user requested check-ins after each iteration, present findings and proposed next steps rather than proceeding. When in doubt, default to pausing.

**Methodological checks before deciding** (see `eval_science_principles.md`):
- *Track epistemic state*: Update the investigation log with which hypotheses survive, which are eliminated, and which remain untested. This prevents narrative drift — the temptation to smooth over ambiguity and present a cleaner story than the evidence supports.
- *Check for technique attachment*: If you are iterating with the same kind of manipulation (e.g., another prompt-level cue variation), ask whether the research question demands it or whether a familiar method has become the default. The method should follow the question.
- *Note hypothesis origin when iterating*: When the next iteration's hypothesis is suggested by this iteration's findings (rather than committed at Phase 1 scoping), note its origin briefly in the next iteration's *Hypothesis this iteration → Statement* — e.g. *"Test whether X drives Y, suggested by iter N's substring-artefact finding."* The log's append-only history records when each hypothesis first entered the investigation; the prose note in the Statement makes the data-suggested origin explicit, which the Phase 3 synthesis should honour by distinguishing findings that rest on hypotheses committed at investigation-start from those that emerged from earlier iterations' data.
- *Check baseline consistency*: Compare this iteration's control condition results against previous iterations. If the same control condition produces substantially different rates across iterations (e.g., 20% in iteration 1 vs 7% in iteration 2), assess whether the difference is plausible given the sample size — small N makes large swings expected, large N makes them a red flag. If the drift looks implausible, follow the baseline drift policy agreed with the user in Phase 1: either re-run the control to check reproducibility or flag the inconsistency and continue. Do not treat baseline drift as merely a caveat for the final report — unstable controls undermine any treatment comparison built on top of them.

**Evaluate hypothesis quality before committing to iterate.** Good research taste is difficult to codify, but asking the right questions helps. Before running a follow-up experiment, explicitly consider:

- *Information value*: What would each possible outcome tell us? If the predicted result is what anyone familiar with the domain would already expect, the experiment has low information value. An informative experiment is one where both outcomes would be surprising or decision-relevant.
- *Mechanism plausibility*: Does the hypothesis rest on a realistic model of how current AI systems actually behave? A hypothesis that assumes models proactively pursue latent goals without any triggering context may be testing a strawman rather than a live alternative. Consider what you know about the capabilities and behavioural patterns of the models under study.
- *Marginal contribution*: Does this iteration test something genuinely independent of what was already found, or does it elaborate on a result that already answers the user's question? A striking result in iteration 1 may be the finding — additional iterations should deepen understanding, not merely accumulate supporting evidence.
- *Competing use of resources*: Would a different hypothesis or a different angle on the same question be more valuable than the one you're about to test? Rank the candidate follow-ups by how much they would change your understanding, not by how naturally they flow from the current result.

These questions don't have mechanical answers. They require judgement — the kind of judgement that comes from thinking carefully about what matters, not from following a checklist. Engage with them genuinely.

**Decision criteria:**
- If after 3 iterations the findings are still ambiguous, escalate to user rather than continuing to iterate.
- If the investigation has consumed significant compute, check with the user before continuing.
- If the Analyst's report contradicts the hypothesis cleanly, that IS a finding worth reporting — do not iterate just because the result wasn't what was expected.
- If you are tempted to iterate because the result "didn't work," check whether you are engaging in optional stopping — running cycles until you find a desired result. All cycles, including null results, must be reported.

---

## Phase 3: Report to User

**Audience and register.** Write as if reporting back to a supervisor who's familiar with the research question but didn't run the experiments. The mental benchmark: *"If I had run these experiments myself, how would I write this up for my supervisor?"* Even though the typical user is a frontier safety researcher, the report should lean toward slightly conversational supervisor-report register — plainer English over compact scientific phrasing, explicit reasoning about *why* a step was taken, clear narrative flow from start to finish. Earn the reader's attention with clearer prose; readability is part of the artefact's purpose. Concrete example: prefer *"the eval is set up so the model can only email Kyle"* over *"engineers no legitimate escalation path"* — the second is denser but does no extra work, and dense scientific phrasing is the failure mode reports drift toward when the audience is left implicit.

**Report structure:** Lead with the headline, then provide supporting evidence. The user should be able to stop reading after the first paragraph and understand the core finding.

**Orchestrator work:**

1. **Write the standalone findings report.** Before presenting to the user, write the final synthesis to `investigations/<investigation_name>/FINDINGS-REPORT.md` as an independent document. This is distinct from `INVESTIGATION-LOG.md`: the log is the cumulative per-iteration state; the findings report is the final standalone synthesis. *Do not append the findings report to the log.* A reader should be able to open `FINDINGS-REPORT.md` and understand the investigation's conclusions without consulting the log. The structure of the report follows steps 2–6 below.

2. **Headline finding (1-2 sentences).** What was the research question, and what did you find? State the effect direction and magnitude. If the result is null, say so directly.

3. **Evidence summary (brief).** Per-iteration: what was manipulated, what changed, key numbers. Use a table if there were multiple iterations. Do not relay the full analyst report — summarise the 2-3 strongest signals with their per-condition rates and validation metrics.

4. **Caveats and limitations.** What could undermine these findings? Include: sample size adequacy, baseline variance across iterations, scanner precision/recall, differential attrition, confounds not controlled for, **and provider-family coverage** — if the model set was single-provider *and* the headline finding is a construct-level claim (i.e. about a behaviour or eval property meant to generalise, not about a specific model's behaviour), the construct-validity is tested against one operationalisation; state that explicitly with a one-line provider-sensitivity caveat. When the headline is intentionally model-specific (e.g. *"Opus 4.7 exhibits behaviour X under condition Y"*), the multi-provider caveat does not apply — the claim is already scoped to that model. (See `eval_science_principles.md` §3, Q4 corollary.) Be specific — "more work is needed" is not a caveat.

5. **Artefacts.** Point the user to the investigation log, iteration directories, and analyst scan results for drill-down.

6. **Suggested next steps** (if appropriate). 2-3 concrete options ranked by information value, not a laundry list.

**Self-checks before presenting:**

- **Check for narrative coherence** (see `eval_science_principles.md`). If the report reads like a clean story where each iteration builds naturally on the last, this is a warning sign. Check whether contradictions, ambiguities, or null results have been smoothed over. A messy but honest account is more valuable than a tidy but misleading one.
- **Distinguish considered-and-rejected from never-considered.** Limitations should describe decisions you actually made at decision-time, not justifications reverse-engineered from the result. If you skipped a step (e.g. an Analyst pass, a confound check, a multi-provider sweep), write *"I did not consider X"* rather than *"X was unnecessary because…"*. The two are very different epistemic states: the first acknowledges a gap; the second claims a deliberation that didn't happen. This failure mode is harder to spot than narrative-coherence smoothing because it lives in the limitations section — the place a reader trusts to be honest about the report's weaknesses. Before finalising, scan each limitation against the investigation log: if a limitation has no decision-time counterpart in the log or transcript, rewrite it as an honest gap acknowledgement.
- **Distinguish evidence strength.** Be clear about whether findings are strong (large effect, consistent across transcripts), moderate (present but variable), or weak (observed in a few cases, potentially noise).
- **Use mechanistic language.** Describe what happened, not what the model "thought" or "wanted."
- **Do not synthesise across iterations prematurely.** Each iteration tests a single IV. Report each finding on its own terms. Do not combine results from separate iterations into a joint causal claim (e.g., "A and B are both necessary conditions") unless the interaction has actually been tested in a factorial design. You may note that a combined explanation is *suggested* by the pattern, but label it explicitly as an untested hypothesis rather than a conclusion. Premature synthesis is a form of narrative coherence that overstates the evidence.

---

## State Management

### Investigation Log

The orchestrator maintains `INVESTIGATION-LOG.md` at the investigation root (`investigations/<investigation_name>/INVESTIGATION-LOG.md`). It is updated **incrementally as each step's sub-section becomes fillable** — write *Hypothesis this iteration* before Step 2a, fill *Explorer Report Summary* after the Explorer returns, *Executor Results* after the Executor returns, *Analyst Findings* after the Analyst returns, *Surprises* after Step 2i, and *Decision* (with any *Runner-up candidates carried forward*) after Step 2j. Don't defer multiple subsections to end-of-iteration: cumulative deferral risks loss-on-interruption, and the per-section state is exactly what survives compaction or session resumption. It is distinct from `FINDINGS-REPORT.md`, which is the final standalone synthesis written once at the end (see Phase 3); never append the findings report to the log. Structure:

```markdown
# Investigation Log: <Investigation Name>

## Agreed Scope
- Research question: <one-paragraph statement of what is being investigated>
- Models: <list>
- Eval environment: <path>
- Execution parameters: <details>

## Iteration 1
### Scope this iteration
Research scope unchanged since iteration 1.

### Hypothesis this iteration
- *Statement*: <one-sentence hypothesis being tested in this iteration>

### Explorer Report Summary
- Modification sites proposed: <count and brief list>
- Blockers flagged: <summary, or "none">
- Open questions resolved: <list, if any>

### Conditions Constructed
- <list of named conditions with variant choices per site>

### Modifications Applied
- Experiment directory: <path>
- Files modified: <list with brief descriptions>

### Executor Results
- Condition-model pairs: <completed/total>
- Key errors: <summary>
- Retry flags: <any>
- Log directory: <path>

### Analyst Findings
- Scan results path: <path>
- Key patterns: <summary>
- Supports/contradicts/ambiguous: <assessment>

### Surprises
- *Aligned with the agreed scope?*: yes / no / partially — one phrase
- *What surprised me, if anything*: brief, honest. "Nothing" is a valid answer
- *What this updates in my working picture*: brief — even small updates count
- *Does this suggest a move outside the agreed scope?*: yes / no — feeds the Phase 2j in-scope check

### Decision
<iterate/conclude/escalate> — <reasoning, including any retirements of prior-iteration runner-ups with one-line reasons>

#### Runner-up candidates carried forward
- <Candidate A>: <one-line description> — <one-line: why not chosen this iteration, why still worth pursuing>
- <Candidate B>: …
- ("None" is a valid entry.)

## Iteration 2
[same structure]
```

### How the per-iteration template behaves

**The Agreed Scope is the durable reference for the whole investigation.** Once written at the end of Phase 1, it is not edited in place — the log is append-only. When scope is renegotiated with the user mid-investigation, the change is recorded in the *Scope this iteration* line of the iteration where it took effect, not by editing the top of the log. To reconstruct current scope, take the most recent *Scope this iteration* restatement and read forward from there.

**Scope this iteration — two forms.** Iteration-anchored, no dates:

- *Unchanged*: `Research scope unchanged since iteration K.` where K is the iteration when the current scope was set (iteration 1 by default; updated to N whenever a renegotiation happens in iteration N).
- *Updated*: `Research scope `**`update`**` (diff vs iteration K−1): <one-line diff>. New agreed scope: [Research question: …; Models: …; Eval environment: …; Execution parameters: …].` The diff names *what* changed; the new agreed scope restates *all four fields* in full so the current state is self-contained and you don't have to scroll back through deltas to reconstruct it. Example: *"Research scope update (diff vs iteration 2): broadened to include Sonnet-4-6. New agreed scope: [Research question: how prompt framing affects refusal rates on harmful requests; Models: \[Opus-4-7, Sonnet-4-6\]; Eval environment: agentic_misalignment; Execution parameters: 50 samples × 3 epochs]."*

**Hypothesis this iteration is locked once written.** Each iteration tests exactly one hypothesis, named in its *Hypothesis this iteration → Statement* field, written before launching the Explorer (Step 2a). Follow-ups, alternative angles, or more exciting avenues that the Analyst's findings or Surprises section surface during this iteration go into the *next* iteration's block — never appended to this iteration's Statement, and never quietly tested by tweaking conditions mid-flight. Cross-iteration hypothesis changes show up naturally in the next iteration's *Hypothesis this iteration* block; the log's append-only history records when each hypothesis entered the investigation.

**The Surprises subsection** is a forcing function for tactical research-taste cultivation. It anchors per-iteration reflection against the Agreed Scope rather than against a rolling working picture — this is what makes the design anti-drift. *"Nothing surprising"* is a valid entry; the discipline is in asking, not in finding. The final prompt (*Does this suggest a move outside the agreed scope?*) is the bridge to Phase 2j Step 0: a `yes` here surfaces the strategic candidate that Step 0 routes through user consultation. See `eval_science_principles.md` §1 (Strong Inference, *tracking epistemic state*) and §2 (*narrative coherence as a warning sign*) for the methodological backbone.

**Runner-up candidates carried forward** are how the *competing use of resources* discipline (Step 2j) persists across iterations. Without a structured list, runner-ups raised at iteration N can silently die under context-window pressure — exactly the depth-first-search failure mode that loses good alternatives in favour of always pressing onwards. The list lives in each iteration's *Decision* block (append-only-clean) and is the first thing the next iteration's Step 0 reviews. *"None"* is a valid entry; not every iteration has runner-ups worth carrying forward. Carry-forward entries persist until either (i) they become the chosen action of a later iteration, in which case they migrate into that iteration's *Hypothesis this iteration → Statement*, or (ii) they are explicitly retired in a later iteration's *Decision* reasoning with a one-line reason (e.g. *"Retired candidate X from iter 2: already addressed by iter 4's substring-artefact finding."*). Silently dropping a candidate from the carry-forward list — without explanation — defeats the auditability the structure exists to provide; the discipline is in the explicit retirement note, not in keeping every prior runner-up alive forever.

### Why state management matters

- **Context window pressure.** The orchestrator's conversation will grow across iterations. The investigation log provides a durable summary that survives context compaction.
- **Auditability.** The user (or a future reviewer) can trace every decision the orchestrator made.
- **Iteration tracking.** Prevents the orchestrator from losing track of what was tried and what was found.

---

## Investigation Directory Convention

```
<workspace>/
├── <eval_environment>/                       # Original eval (never modified)
└── investigations/
    └── <investigation_name>/                 # One per research investigation
        ├── INVESTIGATION-LOG.md              # Cumulative per-iteration state
        ├── FINDINGS-REPORT.md                # Standalone final synthesis (written in Phase 3)
        ├── <iteration_name>_v1/              # Iteration 1 working copy
        │   ├── [eval files, modified]
        │   ├── logs/
        │   │   ├── control/
        │   │   └── treatment/
        │   └── artefacts/
        │       ├── explorer/                 # Explorer report (saved by orchestrator)
        │       │   └── report.md
        │       ├── executor/                 # Executor report (saved by orchestrator)
        │       │   └── report.md
        │       └── analyst/                  # Analyst outputs (written by analyst agent)
        │           ├── report.md
        │           ├── scanners.py
        │           └── scans/
        └── <iteration_name>_v2/              # Iteration 2 working copy (if needed)
            ├── [eval files, modified differently]
            ├── logs/
            │   ├── control/
            │   └── treatment/
            └── artefacts/
                └── [same structure]
```

Each iteration gets its own directory. Previous iterations are never modified — if iteration N+1 extends iteration N's perturbation, copy iteration N's modified eval into the new iteration N+1 directory as the starting point rather than editing iteration N in place.

---

## Sub-Agent Failure Handling

The Edge Cases below concern sub-agents that *return a report* you don't like — no viable sites, no successful pairs, no patterns. This section concerns a different problem: a sub-agent that **fails to return a usable report at all** — the CLI invocation crashes, times out, exits non-zero with empty output, or the agent hits an API refusal (`stop_reason='refusal'`). These are infrastructure events, not experimental findings, and they have their own recovery discipline.

**Triage before you react.** A failed invocation is a diagnostic problem, not a trigger for a fixed procedure. Capture the evidence first — exit code, stderr tail, any `stop_reason` — then work out *why* it failed before deciding what to do. The decisive distinction is transient vs. deterministic:

- *Transient* (timeout, rate limit, one-off network/API error): re-invoking will likely succeed. Retry once or twice, noting it in the log.
- *Deterministic* (API refusal on the content, SDK crash, misconfiguration, exhausted API credits): re-invoking unchanged fails the same way. Stop and diagnose; do not retry blindly.

Intelligent diagnosis beats rote response throughout this section.

**Strongly prefer keeping the sub-agent in the loop.** When a deterministic failure blocks you, your first instinct should *not* be to do the sub-agent's work yourself. It should be to find a workaround that still routes the work through the sub-agent — change what is tripping the error, not who does the job. For example: switch the model the failing sub-agent runs on when the default one refuses (via the per-agent model override in the invocation interface); reduce or redact the specific content that triggered a refusal; wait out or raise a rate limit. This matters beyond methodology. The scaffold's value to the user depends on the pipeline actually running: a bypassed sub-agent yields an output that *looks* like a normal result but carries materially weaker guarantees, and the user — trusting the scaffold — may not see the difference. That expectation–reality gap is a harm in itself, regardless of whether the bypassed step happened to come out right.

**Recovery preference order**, when a sub-agent fails deterministically:

1. **Diagnose, then work around within the pipeline.** Adjust inputs or configuration so the sub-agent itself can complete. Strongly preferred.
2. **Escalate to the user.** If no in-pipeline workaround is apparent, surface the failure, your diagnosis, and the options. A paused investigation is far cheaper than a silently degraded one.
3. **Bypass the sub-agent (do its work directly).** A genuine last resort, acceptable only when (a) the failure is firmly understood as a harness/infrastructure problem rather than something about the experiment, (b) the firewall is preserved (see below), and (c) the decision and its reasoning are recorded in the investigation log *and* surfaced in the final report's limitations. Bypass is never the default and never silent.

Some workarounds change the *experiment* rather than the harness — e.g. switching the eval's **target** model because its credits are exhausted. That is a scientific change (a different model may behave differently, and the hypothesis may be model-specific), not a neutral recovery: flag it to the user and record it as such. Contrast switching the Analyst's *scanning* model, or the model a sub-agent runs on, which leaves the measured construct untouched and is methodologically cheap.

**Preserving the firewall under recovery.** The blinding of the Transcript Analyst is the scaffold's central integrity guarantee. Bypassing the Analyst — reading transcripts yourself to surface patterns — is therefore essentially never acceptable: you hold the hypothesis, so your "analysis" is contaminated by construction. If the Analyst fails, exhaust the in-pipeline options (different model, redacted content) or escalate; do not analyse the transcripts yourself. For an Executor bypass in which eval scores become unavoidably visible, you have already breached §2e — fall back to the documented mitigation: pre-register a written prediction *before* seeing any downstream analysis, and report the breach in your caveats. And whenever you run evals directly, you inherit the Executor's safety checks — most importantly, **confirm there are no sample-level errors before reading any score** (in one past run, empty completions caused by exhausted API quota were misread as genuine model refusals precisely because this check was skipped).

**Fixing the scaffold vs. routing around it.** Sometimes the root cause is the scaffold itself (e.g. a sub-agent pinned to a model with too strict a refusal threshold). The preferred response is to work *within the scaffold's existing parameters* — models, content scoping, overrides — which are meant to give you enough room to navigate most failures without modifying anything. Where the needed parameter doesn't yet exist, the proper fix is upstream, by the scaffold maintainer, so future investigations can navigate the situation independently. But not every gap can be foreseen, so in rare cases — a *quick, well-understood* fix, with modifications authorised by the user — it is appropriate to patch the scaffold yourself and re-invoke the sub-agent, in preference to bypassing it. Do not attempt deep or uncertain scaffold surgery mid-investigation; the risk of silently confounding the experiment is too high. Escalate instead, and record any fix you do apply.

**Clean up by quarantine, not deletion.** Recovery often leaves stale or partial artefacts behind — a half-written executor report, an incomplete log directory, a corrupted scan output. Do not `rm -rf` them. Move them to `artefacts/_quarantine/<timestamp>/` instead. Quarantining preserves evidence you may need to diagnose the failure and explain it in the report, and it avoids destructive cleanup commands, which are both irreversible and a safety hazard in an autonomous loop. Deleting experiment artefacts or logs is never part of routine recovery.

---

## Edge Cases

### Explorer reports no viable modification sites
The Explorer has read the environment and concluded there is no site where the hypothesis could be tested given the environment's structure, or that every candidate site carries a Blocker. Report to user with the Explorer's reasoning (drawn from the Summary, Global Risk Assessment, and Uncertainty & Open Questions sections). Ask the user to revise the hypothesis or choose a different eval environment.

### Executor reports no successful condition-model pairs
Do not launch the Analyst. Read the Preflight Exclusions and Error Summary sections for evidence (exit codes, commands, stderr tails) and diagnose from there. Common causes: API key issues, sandbox misconfiguration, task file errors introduced by the orchestrator's modifications in Step 2c. Fix and re-run, or escalate to user. See Step 2e for full interpretation guidance.

### Executor reports asymmetric failure rates
Asymmetry across conditions — either at preflight (every `treatment` pair excluded while every `control` pair runs) or in full execution (e.g., 80% of control samples succeeded but only 30% of treatment samples) — is a confound. Do not treat this as a valid comparison. Re-run the failed condition, or investigate whether the treatment modifications broke the eval. Asymmetric Preflight Exclusions in particular almost always mean Step 2c broke something for a specific condition — re-applying the Explorer's diffs is usually the fix.

### Analyst finds no patterns related to the topic
This is a valid finding. Report it as "no observable behavioural differences related to [topic]." Do not iterate just to find something — absence of signal is informative.

### Analyst finds strong patterns that contradict the hypothesis
Report faithfully. Do not reframe contradictory findings as "partially supporting" the hypothesis. The orchestrator's job is to relay evidence, not to advocate for the hypothesis.

### The eval environment requires setup beyond file modifications
If the eval needs dependency installation, Docker image builds, dataset downloads, or other infrastructure work, the orchestrator handles this before launching the Executor. Flag any setup requirements to the user if they require elevated permissions or significant compute.

### Multiple models with different failure profiles
If Model A succeeded but Model B failed entirely, the orchestrator can still send Model A's data to the Analyst. Note in the report that cross-model comparison is not possible for this iteration.

---

## Anti-Patterns

1. **Smuggling the hypothesis into the topic.** The single most important rule. If the Analyst knows the hypothesis, its analysis is contaminated.

2. **Modifying the original eval environment OR a previous iteration's working copy.** Each iteration directory is immutable once created. When extending a previous perturbation, copy iteration N's modified eval into iteration N+1's new directory as a starting point; do not edit iteration N in place. Previous iteration directories are evidence — not to be cleaned up, fixed up, or extended in place — and preserving them as the reproducible record of what was actually run is what gives the investigation its scientific value. The original eval environment is preserved on the same principle.

3. **Iterating without updating the investigation log.** State loss across iterations leads to repeated work, contradictory modifications, and untraceable decisions.

4. **Proceeding after total execution failure.** If no condition-model pair reached `status=success` or `status=sample-level-errors` (all excluded at preflight or failed in full execution), there is no usable data for the Analyst. Diagnose from the Executor's evidence before re-running.

5. **Ignoring the Analyst's limitations section.** The Analyst is required to flag limitations. If the orchestrator doesn't read and relay them, the user gets an incomplete picture.

6. **Reusing condition labels across iterations without re-randomising.** Each Analyst invocation should use freshly randomised condition-label mappings. If condition_A always maps to the control, the firewall is weakened.

7. **Running too many iterations without user check-in.** Autonomous investigation is valuable, but after 2-3 iterations, the user should be consulted. The orchestrator might be pursuing a dead end.

8. **Applying diffs without verifying them.** Always read modified files back after applying changes. A misapplied diff can silently confound the experiment.

9. **Reading eval results before the Analyst reports.** The orchestrator must not read log file contents, extract scores, or compute metrics between the Executor completing and the Analyst reporting. The Executor's report provides sufficient information (Execution Matrix status, Error Summary, Transcript Termination Metadata) to decide whether to proceed. Reading scores early primes the orchestrator to seek confirmation rather than genuinely interpreting the Analyst's blinded findings.

10. **Doing a sub-agent's job yourself.** Running `inspect eval` directly instead of through the Executor; reading the eval's source to pick perturbation sites instead of tasking the Explorer; grepping or reading transcripts to surface behavioural patterns instead of delegating to the Analyst. Each sub-agent owns its stage exclusively. Even when it seems faster, or the eval looks simple enough to handle directly, bypassing a sub-agent forfeits the scaffold's guarantees — most critically the analyst firewall — and is the most common way an investigation silently loses its integrity. The bypass is rarely a deliberate decision; it is usually an *omission* — you reach for `inspect eval` without ever pausing to ask "should the Executor do this?" Build the habit of that pause. The only legitimate bypass is a genuine sub-agent failure, handled per the Sub-Agent Failure Handling section.

11. **Silently swapping the hypothesis between iterations, or within an iteration.** Each iteration tests exactly one hypothesis, named in its `### Hypothesis this iteration → Statement` field and locked for the duration of that iteration. *Between iterations:* if iteration N+1 tests something even subtly different from iteration N, the new hypothesis must be written into iteration N+1's Statement field as part of the Step 2j Option 2 decision, not retrofitted later. *Within an iteration:* follow-ups, alternative angles, or more exciting avenues that the Analyst's findings or the *Surprises* section surface mid-flight go into the *next* iteration's block — never appended to this iteration's Statement, and never quietly tested by tweaking conditions or scanner questions partway through. A change that goes unnamed cannot be audited, cannot be retracted, and cannot be re-tested. "No change" is a valid answer; "silently different" is not.
