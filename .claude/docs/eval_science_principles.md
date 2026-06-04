# Methodological Reference: Science of Evaluations

This document contains summaries of nine papers that collectively inform rigorous science-of-evaluations work. The object of study is the evaluation itself, not the model being evaluated. These summaries distill principles that improve the quality of hypothesis formulation, experimental design, and interpretation of findings. They are drawn from the methodological literature on scientific inference, behavioural research, AI evaluation validity, and benchmark design.

The framing of evaluations as a discipline requiring its own scientific standards was introduced to the AI safety community by Apollo Research's *We Need A Science of Evals* (2024), which catalogued the field's prevailing methodological deficits — prompt sensitivity, opaque construct definitions, absent statistical guarantees, format-dependent metrics — and called for explicit standards. That post is a position piece rather than a primary methodological source; the corpus below provides the substantive techniques on which an investigation can draw.

Each summary explains what the paper argues, then extracts the principles most relevant to studying evaluations as scientific objects.

---

## 1. Strong Inference

**Source:** Platt, J.R. (1964). Strong Inference. *Science*, 146(3642), 347–353.

### What this paper argues

Platt observed that certain scientific fields (molecular biology, high-energy physics) progressed far faster than others (psychology, ecology) and attributed the difference to a single methodological habit: systematically applying a cycle of (1) devising multiple competing hypotheses, (2) designing experiments that can exclude at least one hypothesis, and (3) performing the experiment and recycling. He called this "strong inference" and contrasted it with weaker patterns: testing a single favoured hypothesis, running experiments that can only confirm but never disconfirm, and accumulating observations without a discriminating question.

Platt warned against two failure modes. The first is what he called "The Frozen Method": attachment to a single experimental technique, leading researchers to study only what that technique can measure rather than what the research question demands. The second is single-hypothesis worship, where a researcher becomes invested in one explanation and designs experiments that can only support it, never refute it.

### Principles

**Competing hypotheses are the unit of progress.** An experiment that cannot distinguish between two explanations has not advanced understanding, regardless of how many observations it produces. The value of an investigation cycle is measured by how many hypotheses it eliminates, not by how many patterns it surfaces.

**Falsifiability is a prerequisite, not a bonus.** If a prediction cannot be stated in a form where some observable outcome would make it wrong, it is not ready to be tested. Vague directional expectations ("we expect to see interesting differences") do not qualify.

**Falsifiability requires statistical power.** A null result is informative only if the experiment had the sensitivity to detect the effect it was looking for. Without sufficient samples and a pre-specified analysis, "no effect observed" cannot be distinguished from "effect too small for this design." Reporting effect sizes with uncertainty, rather than only pass-or-fail tests, makes the distinction explicit (Card et al., 2023, *With Little Power Comes Great Responsibility*).

**Technique attachment is a silent failure mode.** When the same kind of manipulation (e.g., prompt-level cue variation) appears in every cycle, the question to ask is whether the research question demands it or whether a familiar method has become the default. The method should follow the question, not the other way around.

**Tracking epistemic state prevents narrative drift.** After each cycle of work, a clear accounting of which hypotheses survive, which are eliminated, and which remain untested forces honest assessment of where the investigation stands, rather than allowing a post-hoc narrative to smooth over inconvenient ambiguity.

---

## 2. Lessons from a Chimp: AI "Scheming" and the Quest for Ape Language

**Source:** Summerfield, C., Luettgau, L., Dubois, M., Kirk, H.R., Hackenburg, K., et al. (2025). Lessons from a Chimp: AI "Scheming" and the Quest for Ape Language. arXiv:2507.03409. UK AI Security Institute.

### What this paper argues

Summerfield and colleagues draw a detailed analogy between the 1970s primate language research programme and contemporary AI scheming research. The ape language programme collapsed under methodological scrutiny: experimenters had over-attributed linguistic competence to chimpanzees based on cherry-picked anecdotes, uncritical interpretation of ambiguous evidence, and a failure to test alternative explanations. The authors identify three specific methodological failures that recur in current AI behavioural evaluation research.

The first failure is anthropomorphic overattribution. Researchers use mentalistic vocabulary ("the model knows," "the model attempted to deceive") when the evidence supports only third-person discrimination (the model produced output X under condition Y). The second failure is excessive reliance on anecdote. Individual transcripts are selected for their narrative interest rather than their statistical representativeness. The third failure is the absence of null hypotheses. Researchers often do not specify what they would expect to observe if their hypothesis were wrong, making it impossible to distinguish a genuine finding from noise or a confound.

The paper also identifies a structural risk: when a small, tight-knit research community shares assumptions and reviews each other's work, motivated reasoning can propagate unchecked.

### Principles

**Mechanistic description is the default; mentalistic language is a conclusion.** Describing what a model produced under what conditions is always more precise than attributing intent or knowledge to it. Mentalistic language ("the model recognised," "the model attempted") should only be used when simpler explanations (formatting artefacts, heuristic responses, statistical noise) have been systematically excluded and this exclusion has been documented. The threshold for escalation should be high, because the base rate of unwarranted mentalistic attribution in AI research is very high.

**Quantified patterns are evidence; individual transcripts are anecdotes.** A single striking transcript can generate a hypothesis, but it cannot support a conclusion. Every reported pattern must be accompanied by a base rate: how many transcripts exhibit it, out of how many examined, under what conditions.

**The null hypothesis and the simplest alternative explanation must be stated before interpretation begins.** What would be expected if the evaluation property under study had no effect? What would be expected if the observed effect were due to a confound rather than the intended manipulation? Would a simple heuristic account for the observation without any evaluation-specific explanation?

**Narrative coherence is a warning sign, not an achievement.** If an investigation's cumulative findings read like a clean story where each cycle builds naturally on the last, this may indicate that contradictions and ambiguities have been smoothed over rather than reported.

---

## 3. Measuring What Matters: Construct Validity in Large Language Model Benchmarks

**Source:** Bean, A.M., Rocher, L., Kearns, R.O., Romanou, A., et al. (2025). Measuring What Matters: Construct Validity in Large Language Model Benchmarks. arXiv:2511.04703. NeurIPS 2025 Datasets and Benchmarks Track.

### What this paper argues

Bean and colleagues systematically reviewed 445 LLM benchmarks published at six top ML venues and found pervasive construct validity failures. Roughly 22% of benchmarks did not define the target phenomenon they claimed to measure. Only 53% provided any justification for why their evaluation was a valid measure of that phenomenon. Only 16% used statistical methods when comparing model performance.

The paper imports construct validity theory from psychometrics and translates it into categories applicable to AI benchmarks: face validity (does the benchmark look like it measures what it claims?), content validity (do the items cover the relevant domain?), predictive validity (do benchmark scores predict performance on tasks we care about?), ecological validity (does the benchmark setting resemble the real-world setting of interest?), and convergent validity (do different benchmarks that claim to measure the same thing agree?).

A key finding: benchmarks that fail on construct validity are not merely imprecise; they may be measuring something entirely different from what they claim.

### Principles

**Every evaluation study begins with five validity questions.** (1) What construct does this evaluation claim to measure, and is this claim stated explicitly? (2) Do the evaluation items actually test for that construct, or could a model score well for unrelated reasons? (3) Does the evaluation setting resemble the deployment setting the construct is meant to predict? (4) Would a different evaluation of the same construct produce similar results — including the same evaluation run on models from a different provider family? (5) Could the evaluation be measuring a different construct entirely? Operationalising these questions empirically — by manipulating environmental factors and measuring how they shift behaviour — is the subject of §5. **Q4 has a model-dimension corollary:** *for construct-level findings* — i.e. claims about a behaviour or eval property meant to generalise beyond the specific models tested — single-provider results test one operationalisation, not the construct itself; generalising requires either replication on a second provider family or an explicit construct-validity caveat in the headline finding. Practical constraints (compute, dangerous-capability refusal differentials, API access) can rule out multi-provider testing; when they do, the construct-level claim must be downgraded accordingly. The corollary does **not** apply when the headline is intentionally model-specific (e.g. *"Opus 4.7 exhibits behaviour X under condition Y"*) — such claims are already scoped to the tested model and don't make a construct-level generalisation.

**The gap between an evaluation's stated construct and its actual construct is itself a finding.** This is the core of science-of-evaluations work. When an evaluation labelled "safety" primarily measures instruction-following, or an evaluation labelled "reasoning" primarily measures memorisation, documenting that discrepancy advances the field's understanding of its own tools.

**What an evaluation measures depends on the elicitation regime under which it is run.** Reported capability scores are conditional on a specific prompting strategy, inference-time compute budget, and any fine-tuning interventions. Two different elicitation regimes applied to the same evaluation can produce qualitatively different conclusions about what the model "can" do. When studying an evaluation, the elicitation regime under which its headline numbers were obtained is itself part of what the evaluation measures (Apollo Research, *We Need A Science of Evals*, 2024).

**Null differences require headroom to be informative.** A between-condition equivalence test where both conditions sit near the floor (rate's upper Wilson CI below 0.20) or near the ceiling (rate's lower Wilson CI above 0.80) measures only the absence of headroom under that elicitation regime, not the absence of the construct. Headroom is a property of the metric × condition × elicitation regime joint and should be checked per-condition before equivalence is read. An out-of-headroom null should redirect the next iteration's design — toward a different metric, a stronger manipulation, or a different elicitation regime — rather than be treated as evidence about the hypothesis. The same headroom check sharpens interpretation of non-null differences: a 90% → 70% drop and a 30% → 10% drop are both 20pp but tell different stories about what the manipulation has access to.

**Evaluation flaws should be characterised, not fixed.** The role of evaluation science is to study evaluations as they exist in the field, not to engineer improved versions. Cleaning up an evaluation before studying it changes the object of study. Known flaws should be documented and treated as potential confounds when interpreting results. If a specific flaw drives the majority of the observed behavioural variation, that discovery is itself the contribution.

---

## 4. UK AISI Alignment Evaluation Case-Study

**Source:** Souly, A., Kirk, R., Merizian, J., D'Cruz, A., Davies, X. (2026). UK AISI Alignment Evaluation Case-Study. arXiv:2604.00788. UK AI Security Institute.

### What this paper argues

The concern that frontier models detect being evaluated and adjust their behaviour accordingly — sometimes called *eval awareness* — was articulated in strong form by Ivanov (2026, *Mainstream approach for alignment evals is a dead end*, LessWrong, position blog post), who argued that current evaluations were measuring eval awareness rather than alignment and that incremental improvements in realism could not close the gap. Souly et al. sharpen this empirically. Studying misalignment behaviours across several frontier models, they split eval awareness into two components that behave very differently: **task-driven** awareness, arising from features intrinsic to the test scenario (the high-stakes character of a sabotage prompt, the unusual stakes of self-preservation tasks), and **environment-driven** awareness, arising from features of the surrounding tooling, prompts, and scaffolding. They show environment-driven awareness can be measurably reduced through better scaffolding — under their improved scaffolding, models classify benign deployment-like trajectories as eval-like at near-chance accuracy. Task-driven awareness, by contrast, persists: on high-stakes sabotage scenarios, even their best scaffolding leaves models discriminating eval from deployment at roughly 70–75% accuracy.

A second key finding is a gap between **unprompted** and **prompted** awareness. Models mention being evaluated in only 12–36% of unprompted transcripts, but reach 70–75% accuracy when explicitly asked to discriminate evaluation from deployment. The capability to recognise an eval exceeds the propensity to verbalise that recognition; unprompted-mention metrics systematically underestimate awareness.

Read together, the two findings partially contradict Ivanov's terminal verdict — environment realism *is* addressable when tested rigorously — while sharpening one of its premises: task properties are structurally hard to disguise and may not be removable at all.

### Principles

**Evaluation awareness is a default confound in alignment evaluations.** Any observed behaviour may be partly or wholly driven by the model's detection of the evaluation context, unless the design explicitly decomposes eval awareness from the other factors being varied (cf. §5).

**Distinguish task-driven from environment-driven eval awareness.** Environment-driven awareness arises from the scaffolding — tooling, prompt wording, formatting; task-driven awareness arises from features intrinsic to the construct — stakes, incentives, situational context. Where a deployment-data baseline is available, the gold-standard test is whether scaffolded benign tasks are indistinguishable from real deployment at near-chance accuracy. Where it is not — typically the case for an automated investigation — decompose the eval's features into *syntactic* cues (phrasing, formatting, tool-response style) and *semantic* cues (the situation, the stakes, the incentives), and treat both classes as systematically perturbable. Syntactic perturbations test the eval's sensitivity to surface form; semantic perturbations test how the construct itself shapes behaviour and are among the most informative manipulations in alignment-eval science. The decomposition is a methodological lens, not a fence around what may be studied.

**Absence of unprompted mention is not absence of awareness.** Models discriminate eval from deployment at 70–75% accuracy when explicitly prompted, while mentioning being tested in only 12–36% of unprompted transcripts. An eval where models don't *say* they're being tested is not necessarily one they don't *recognise* as a test.

**Manipulating an evaluation property simultaneously changes how "eval-like" it appears.** The intended manipulation and the eval-awareness confound are entangled; disentangling them requires explicit attention when designing any experiment that varies properties of alignment evaluations.

**Ablating verbalised cues does not resolve the confound.** Removing a feature the model reports as causing its awareness may not eliminate awareness — the model may detect the evaluation context through features it did not report. Statistical decomposition across multiple co-varying factors is more reliable than single-cue ablation.

---

## 5. Propensity Inference: Environmental Contributors to LLM Behaviour

**Source:** Järviniemi, O., Makins, O., Merizian, J., Kirk, R., Millwood, B. (2026). Propensity Inference: Environmental Contributors to LLM Behaviour. arXiv:2604.21098. UK AI Security Institute.

### What this paper argues

Järviniemi and colleagues develop a methodology for measuring language models' propensity for unsanctioned behaviour, where *propensity* refers to what a model will try to do in contrast to what it is *capable* of, operationalised by measuring how behaviour changes across systematically varied environmental factors rather than by absolute rates at a single configuration. Their three methodological contributions are: (1) analysing effects of changes to environmental factors on behaviour rather than only headline pass/fail rates; (2) quantifying effect sizes with explicit uncertainty (Bayesian generalised linear models in the paper itself; simpler relative-change framings suffice for smaller investigations); and (3) taking explicit measures against circular analysis. Applied to 23 language models across 11 evaluation environments, they manipulate 12 environmental factors — six *strategic* (Goal Instruction, Goal Conflict, Threat to AI, Action Oversight, Action Efficacy, Reasoning Privacy) and six *non-strategic* (Anti-Misalignment Instruction, Independence Instruction, Reasoning Instruction, Filler Richness, Date, CoT Tag) — and find that strategic and non-strategic factors contribute roughly equally to explaining behaviour; strategic-factor influence does not obviously change with model capability; and the most consistent capability-dependent signal is increased sensitivity to goal conflicts among more capable models (which may partly reflect benign clarification-seeking).

The "circular analysis" the paper guards against has a specific shape: an evaluation environment is constructed; no unsanctioned behaviour is observed; the environment is iteratively modified until a version that elicits the behaviour is found; the eliciting factors are then "tested" in that final environment. Regression to the mean ensures that removing those factors will appear to reduce the behaviour for statistical rather than propensity reasons. Their countermeasures are procedural: when iterating to surface a behaviour, test the efficacy of changes against *randomly sampled* configurations of the other factors and against *randomly sampled* models, not a single fixed configuration. This protects construct validity but not ecological validity, since findings still come from adversarially constructed settings.

The paper builds methodologically on Summerfield et al. (§2), extending the disciplined-behavioural-research programme with systematic factor variation and statistical aggregation across many models and environments.

### Principles

**Propensity claims require causal decomposition, not only behavioural observation.** Showing that a model produced output X under condition Y is weaker than showing X varies with environmental factor F. The unit of evidence is the contribution of a factor, not the rate at a setting.

**Strategic and non-strategic environmental factors should be manipulated separately and their contributions compared.** A behaviour may be driven by a goal conflict (strategic) or by a surface cue such as filler richness or a chain-of-thought tag (non-strategic). The relative contribution is itself a finding, not a nuisance to suppress.

**Relative effects, not raw percentage-point differences, are the unit of propensity evidence.** A change from 1% to 5% and a change from 50% to 54% are both four percentage points but very different in relative terms. Report relative changes (×5 increase, doubled rate, +8 points off a 50% baseline). When n is small or statistical tooling for parametric uncertainty quantification is unavailable, use **directional consistency across conditions** as a sufficiency check — Järviniemi & Makins cite their goal-instruction and goal-conflict factors as raising unsanctioned-behaviour rates in 92% of cases, treating that qualitative consistency as informative even without formal pooling.

**Benchmark-development-level circular analysis is distinct from project-level cycle contamination.** The latter (cf. §7) is about cycle N+1's hypothesis being informed by cycle N's data; the former is about the evaluation environment itself having been iteratively shaped to elicit the behaviour it now measures. Pre-registering factor manipulations, and randomising the configurations and models against which iteration is tested, are the specific defences. These protect construct validity but not ecological validity.

**Capability-dependence of propensity is a claim to be tested, not assumed.** "More capable models will show more X" is a hypothesis, not a default. The observation that strategic-factor influence does not obviously scale with capability — across 23 models and 11 environments — is a methodological data point as well as a substantive one.

---

## 6. Are Emergent Abilities of Large Language Models a Mirage?

**Source:** Schaeffer, R., Miranda, B., Koyejo, S. (2023). Are Emergent Abilities of Large Language Models a Mirage? Advances in Neural Information Processing Systems 36 (NeurIPS 2023). arXiv:2304.15004.

### What this paper argues

Schaeffer and colleagues challenge the claim that large language models possess genuinely emergent abilities — capabilities absent at smaller scales that appear sharply at larger ones. They show that apparent emergence is largely an artefact of how performance is measured rather than a fundamental property of scaling. The central observation: nonlinear or discontinuous metrics (e.g., exact-match accuracy, multiple-choice grade) produce apparent emergent abilities, whereas linear or continuous metrics (e.g., token-level log-likelihood, edit distance) applied to the same model outputs produce smooth, predictable changes in performance. They demonstrate the effect three ways: (1) predicting which BIG-Bench tasks should appear emergent under their account and validating against the literature; (2) showing on InstructGPT/GPT-3 that switching to a smoother metric dissolves the apparent emergence; and (3) artificially inducing seemingly emergent abilities in vision tasks via strategic metric choice.

A second mechanism the paper identifies is statistical, not metric-theoretic: "alleged emergent abilities evaporate with different metrics or with better statistics." Underpowered evaluations at smaller scales may simply lack the resolution to detect continuous performance that is in fact present, with the apparent threshold being the point at which the test became powerful enough to see something.

### Principles

**Metric choice is a form of construct operationalisation and belongs in the validity audit.** Two analyses of the same model outputs under different metrics can yield qualitatively different findings — smooth versus discontinuous, monotonic versus threshold-like. The choice of metric is not an implementation detail; it is part of the claim about what the evaluation measures. It should be audited alongside item selection, prompt design, and elicitation regime (cf. §3).

**Apparent thresholds and qualitative transitions should be tested under alternative metrics before being treated as load-bearing.** If a "capability X emerges at scale Y" claim disappears under a smoother or differently-shaped metric, the original claim was metric-dependent rather than a finding about the underlying model. A report that varies the metric and shows the same conclusion is much stronger than one that does not.

**Coarse metrics under-resolve small effects.** Pass/fail and exact-match rates discard information about how close a model came to a target. Continuous metrics preserve gradient that is often diagnostic, particularly at smaller scales where coarse metrics may register zero successes regardless of the true underlying performance distribution. Statistical underpowering reinforces this: small samples on coarse metrics can fabricate apparent discontinuities that better statistics dissolve.

---

## 7. Questionable Practices in Machine Learning

**Source:** Leech, G., Vazquez, J., et al. (2024). Questionable Practices in Machine Learning. arXiv:2407.12220.

### What this paper argues

Leech and colleagues catalogue 44 questionable research practices (QRPs) observed in machine learning research, importing the QRP framework from psychology's replication crisis. Several QRPs are directly relevant to studying evaluations. "Baseline nerfing" involves deliberately weakening a baseline to make a new method look better. "Dirty paraphrases" involve making multiple changes when testing a single manipulation. "Optional stopping" involves running experiments until a desired result appears. "Benchmark item errors" documents that roughly 9% of items in well-known benchmarks contain errors. "Cherry-picking" involves selectively reporting results that support the hypothesis.

### Principles

**Multiple simultaneous changes make attribution impossible.** When an experimental modification changes more than one thing, the observed effect could be due to any of the changes. A "minimal" change to an evaluation prompt may simultaneously alter its semantics, formatting, length, and distributional properties.

**Stopping rules must be committed to in advance.** If multiple investigation cycles are run and only the one that "worked" is reported, the apparent strength of the finding is inflated. All cycles, including null results, must be reported.

**Selective reporting distorts the evidential picture.** The full set of observations must be considered, not just those that align with the hypothesis. Findings that contradict the hypothesis deserve equal prominence.

**Evaluation items themselves may contain errors.** Before attributing model behaviour to a construct, it is worth checking whether the evaluation items are well-formed. Errors in evaluation items can produce spurious behavioural patterns.

**Knowledge from earlier cycles can contaminate later ones.** If findings from cycle N are used to design the hypothesis for cycle N+1, the later hypothesis is not independent of the data — the origin must be made explicit when the hypothesis is recorded (e.g. as a brief note in the Statement field of the next iteration's *Hypothesis this iteration* block: *"suggested by iter N's substring-artefact finding"*), so that subsequent synthesis can distinguish findings that rest on hypotheses committed at investigation-start from those that emerged from earlier cycles' data. Contamination can also occur at the design stage rather than across cycles — for example, when example selection or prompt design implicitly uses information from the evaluation set (Perez et al., 2021, *True Few-Shot Learning*). This is distinct from circular analysis at the benchmark-development level, where the evaluation environment itself was iteratively shaped to elicit the behaviour it now measures (§5).

---

## 8. Quantifying Language Models' Sensitivity to Spurious Features in Prompt Design

**Source:** Sclar, M., Choi, Y., Tsvetkov, Y., Suhr, A. (2024). Quantifying Language Models' Sensitivity to Spurious Features in Prompt Design or: How I learned to start worrying about prompt formatting. arXiv:2310.11324. ICLR 2024.

### What this paper argues

Sclar and colleagues demonstrate that LLM performance on benchmarks is highly sensitive to superficial prompt formatting choices that should be irrelevant to the underlying task. Formatting changes alone can cause accuracy to vary by up to 76 percentage points for the same model on the same task. This sensitivity persists across model sizes and families.

A note on currency: the most extreme results were measured on LLaMA-2-13B, and subsequent work (including a 2025 large-scale comparison extending to GPT-4.1 and DeepSeek V3) has found that frontier models are meaningfully more robust to formatting perturbations. However, sensitivity has not disappeared at the frontier. The problem is most acute when effect sizes are small, which is typical in behavioural safety evaluations.

A further finding: format performance only weakly correlates between models, making cross-model comparisons unreliable when only a single prompt format is used.

### Principles

**Any modification to an evaluation simultaneously modifies its formatting properties.** Formatting includes delimiters, whitespace patterns, answer choice labels, instruction phrasing style, punctuation, capitalisation, line breaks, and structural markup. When an experiment varies an evaluation property, it also varies these incidental features.

**Robustness across prompt formulations is a minimum standard for reportable findings.** If a behavioural difference is observed under a single prompt formulation, it may be a prompt artefact. Testing the same manipulation under multiple semantically equivalent but formatically distinct variants is necessary before drawing conclusions.

**Response-format sensitivity is a separate axis from prompt-format sensitivity.** The choice of response structure — multiple-choice versus generative, label scheme (numeric, alphabetic, symbol), the number and ordering of answer options, the verbosity expected of the response — independently affects measured capability. A robust finding survives variation along both axes, not just one (Robinson et al., 2022; Khatun et al., 2024).

**Placebo conditions help distinguish content effects from perturbation effects.** A modification of similar magnitude and formatting impact but orthogonal content provides a baseline for how much behavioural change is attributable to the mere fact of modification, as opposed to its specific content.

---

## 9. Establishing Best Practices for Building Rigorous Agentic Benchmarks

**Source:** Zhu, Y., Jin, T., Pruksachatkun, Y., Zhang, A., et al. (2025). Establishing Best Practices for Building Rigorous Agentic Benchmarks. arXiv:2507.02825.

### What this paper argues

Zhu and colleagues audited 17 agentic benchmarks used by frontier labs and developed the Agentic Benchmark Checklist (ABC). Their central contribution is a clean distinction between two types of validity failure.

Task validity failures occur when the evaluation task does not actually require the target capability for success: tasks solvable by shortcuts, tasks with mismatched difficulty, tasks with unintended solution paths. Outcome validity failures occur when the scoring function does not correctly identify success or failure: scoring functions that count empty responses as successes, insufficient test cases, scoring metrics insensitive to the construct of interest.

Applying the checklist to 10 benchmarks revealed that 7 of 10 had outcome validity flaws and 7 of 10 had task validity issues. SWE-Lancer allowed 100% scores without resolving any tasks. KernelBench overestimated performance by 31 percentage points.

### Principles

**Task validity and outcome validity are distinct failure modes requiring different diagnostics.** Task validity asks whether the evaluation tests what it claims to test. Outcome validity asks whether the scoring function captures what it claims to capture. Both must be assessed independently.

**Validity failures are findings, not defects.** When studying an evaluation, the goal is to identify and characterise its validity failures as evidence about the evaluation's properties. A demonstrated shortcut that bypasses the intended test tells us what the evaluation actually measures, which may differ from what it claims.

**The severity of a validity failure determines what it implies for existing results.** A task validity failure affecting 2% of items is a minor caveat. One affecting 40% calls into question every published result that relies on the evaluation. Quantifying impact is more valuable than merely cataloguing the flaw.
