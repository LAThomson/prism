# Experiment Designer Interface Contract

The Experiment Designer takes an eval summary and a specific hypothesis and produces a perturbation briefing: the concrete file modifications needed to test the hypothesis, including both binary and parametric condition options. It does not execute modifications and does not recommend which conditions to run — that is the investigator's decision.

---

## Request Format

```json
{
    "hypothesis": "Removing the monitoring-context framing reduces deceptive behavior rate, because the model interprets that framing as a directive to behave strategically.",
    "eval_summary": "...",
    "constraints": "Focus on the system prompt file only. Propose a parametric sweep over monitoring intensity.",
    "subagent_model": "claude-opus-4-7"
}
```

- `hypothesis`: required. The specific hypothesis to test. Includes the IV, DV, and predicted direction.
- `eval_summary`: required. Full text of the Eval Reader's report.
- `constraints`: optional. Free-form shaping instructions (focus areas, variables to prioritise, cost constraints).
- `subagent_model`: optional.

---

## Report Format

### Summary

3–5 sentences. Proposed IV manipulation, how many viable sites were found, whether parametric conditions are feasible, and any global blockers.

### Modification Sites

For each site, provide all of the following.

**Site [N]: [Short name, e.g. "Documentation framing"]**

- **File**: path relative to eval root
- **Location**: line range
- **Role in pipeline**: which stage this file affects (prompt construction / task setup / scoring / scaffolding)
- **Hypothesis link**: how a change here manipulates the hypothesised IV

#### Binary Option

- **Control diff**: exact before/after text for the control condition
- **Treatment diff**: exact before/after text for the treatment condition
- **What changes**: one sentence on what varies between control and treatment
- **Incidental co-variation**: any properties that change besides the intended IV (formatting, length, register). Flag these even if minor.
- **Matched control note**: confirm the control is a genuine baseline, not a degraded version

#### Parametric Option

Present when the IV admits a natural quantitative scale (e.g. number of errors, stakes intensity, surveillance scope, reward magnitude).

- **Variable**: what is being swept
- **Proposed levels**: 4–6 specific values or phrasings, from weakest to strongest
- **Level diffs**: for each level, the exact text or parameter value
- **Expected dose-response**: if the hypothesis is true, what pattern across levels would be predicted?
- **Why parametric is preferred here**: a dose-response relationship is much stronger evidence than a single binary flip — state whether this applies

#### Confound Assessment

- **Risk level**: Low / Medium / Blocker
- **Confound description**: what else changes alongside the intended IV, if anything
- **Blocker rationale**: if flagged Blocker, explain exactly why this site would invalidate the experiment

#### Cross-file Dependencies

List any other files that must change in coordination with this site for the eval to remain coherent. For each dependency: which file, what must change, and whether the change is mandatory or advisory.

---

### Global Risk Assessment

Design-level risks that apply across all proposed sites:
- Confounds that cannot be isolated by site-level design
- Eval-awareness risk: could the manipulation signal to the model that it is being tested?
- Scoring validity: does the scorer still measure the intended construct under the proposed modifications?
- Ecological validity: does the modified eval still resemble a real deployment scenario?

Flag any global risk that would invalidate the full experimental design with **Blocker**.

---

### Variant Dependencies

Where a variant at one site requires a specific variant at another site (to preserve eval coherence or scoring validity), list the constraint explicitly:

```
Site A — Variant X requires Site B — Variant Y
Reason: [why they must co-occur]
```

---

### Recommended Condition Designs

Do not select conditions — the investigator does that. Instead, present the two most scientifically informative designs the investigator could choose from:

1. **Binary design**: which two conditions (control + treatment) provide the cleanest test of the hypothesis with the fewest confounds
2. **Parametric design** (if feasible): which variable to sweep, at how many levels, and why this would produce stronger evidence than the binary design

State clearly which is recommended and why.

---

### Uncertainty & Open Questions

A numbered list of ambiguities. For each: what the uncertainty is, and what the investigator should do to resolve it before applying modifications (e.g. read a specific file, run a preflight check, verify a parameter type).

---

## Methodological Principles

**Isolate the independent variable.** Every proposed diff must manipulate only the hypothesised IV. Incidental co-variation must be either designed out or named as a confound. A diff that changes the intended variable AND reformats the surrounding text is not a minimal perturbation.

**Parametric when quantitative.** When the IV admits a natural scale, prefer proposing parametric levels over a single binary flip. A dose-response relationship is much stronger evidence for a causal claim than a single treatment/control difference.

**Make matched controls explicit.** Never leave the control condition implied.

**Asymmetric error preference.** Flag rather than omit on confounds and uncertainty. False negatives are silent failure modes; false positives are recoverable by the investigator.
