# Phase −1 — Project Planning (Web Chat Session)

## Purpose
Document the planning conversation that produced `00_PROJECT_CONTEXT.md`. This phase happened in Claude.ai web chat (Opus 4.7) between the human and AI, before any code was written. Output of this phase is the handoff doc and all locked decisions it contains.

## Inputs / Outputs
- Inputs: raw project description (STAT 4010/5010 Option #2), three data files (`nba_national_ratings.csv`, `dmas.csv`, `nba_team_athlete_followership.xlsx`), human's initial research intuition ("predict NBA ratings, team form probably matters")
- Outputs: `00_PROJECT_CONTEXT.md` (the handoff), locked research direction (E), locked variable list, locked model spec, locked decomposition method, locked robustness-check scope

## Key results
- Research question locked: "What drives NBA national TV ratings?"
- Approach: log-linear GLM + LMG variance decomposition + bootstrap CIs
- 6 driver families identified (star power, market size, team form, matchup, network, timing)
- Data acquisition strategy: `hoopR` in R, with pre-modeling diagnostics as mandatory first step
- Paper scope discipline enforced: 2 robustness checks only, each writeup ≈ 1 page

## --- HUMAN EVALUATION SECTIONS ---

### Decisions made in this phase
- Picked Direction E (driver decomposition) over A–D, F, G
- Excluded NBA-TV (286 rows) from analysis
- Excluded All-Star Weekend events (8 rows)
- Target = `log(P2+)` primary, `log(P18-49)` robustness
- LMG as primary decomposition, `hier.part` as sanity check
- `hoopR` as data source, with hard-stop diagnostic checkpoint
- Exactly 2 robustness checks (P18-49 swap, pre-new-deal subsample)
- Writeup discipline: ≈1 page each, with mandatory human-collaboration log

### Assumptions relied on
- 3 seasons × ~700 games post-dedup provides enough power for 13-predictor model
- End-of-period follower snapshot is acceptable proxy for per-game star power (relative ranking of "who's a star" is stable year-to-year)
- hoopR will achieve ≥95% match rate against ratings data (to be verified in Phase 0)
- 6 driver families map cleanly onto course tools (regression, ANOVA-style decomposition, bootstrap, diagnostics)

### Alternatives considered but not chosen
- **Direction C′ (network / media-rights transition focus)** — rejected in favor of E because "what drives ratings" is more scope-appropriate for 5–8 pages than a transition study
- **Direction D (star power focus)** — rejected; E subsumes it as one of 6 families
- **Gamma GLM with log link** — rejected because `relaimpo` requires `lm` object; log-linear OLS achieves same goal
- **PMVD decomposition** — unavailable in US (patent issue); LMG mathematically equivalent to Shapley and sufficient
- **More than 2 robustness checks** — rejected to protect paper length

### Risks / things a human should double-check
- Follower snapshot temporal mismatch is a real measurement-error source — Phase 0 diagnostics should quantify the magnitude
- Toronto Raptors has no US DMA record — handoff doc flags imputation with mean; teammates should verify this isn't absurd
- Rollup-row dedup logic is non-trivial; Phase 0 should sanity-check that no game is double-counted and no game is accidentally dropped
- NBA-TV exclusion is a strong a priori choice; if reviewers want to see it, rerunning with NBA-TV included as a robustness check is straightforward

### Code quality self-assessment
No code was written in this phase — only planning. Handoff doc has been audited for internal consistency (every variable referenced in the model spec has a defined source). One place remaining judgment calls left to Claude Code: imputation strategy for missing starter follower counts, final treatment of traded-player rows in follower file.

## --- HUMAN COLLABORATION LOG ---

### Human inputs / decisions that shaped this phase

- **Initial framing: "efficiently predict NBA ratings"** → started conversation in predictive mode; later reframed to inferential (driver decomposition)
- **"Team on fire as binary, records via NBA API"** → confirmed hoopR as right tool; this intuition became the "team form" family
- **"Short paper 5–8 pages, targeted and precise, not broad"** → forced scope discipline; directly drove decision to limit to 2 robustness checks and ~1 page per writeup
- **Mid-conversation: added social follower data + injury-adjusted starting 5 logic** → triggered full rethink of direction options; made D (star power) briefly the recommended direction before user chose E
- **Chose Direction E over my D+ recommendation** → shifted from single-headline paper to horse-race framing; triggered LMG decomposition plan
- **Chose hoopR but demanded "diagnostics first to check completeness and sense"** → added Phase 0 hard-stop checkpoint to the plan; upgraded data-quality rigor
- **Asked "what decompositions methods you think of and how they relate to ANOVA?"** → substantive methodological probe; my response became part of the paper's methods framing
- **Locked LMG + hier.part sanity check over LMG-only** → added unique-vs-shared variance analysis that will strengthen the star-power-vs-market-size discussion
- **Requested concise bullet-point style throughout** → drove writeup template toward short, scannable format
- **Requested 3-collaborator workflow via GitHub** → shaped gitignore (commit figures/tables/PDF) and README guidance
- **Requested mandatory human-collaboration logs in every writeup** → added new template section §14.2; without this, the paper's AI-evaluation section would be unwritable

### Human questions answered in-chat

- Q: Which decomposition methods exist and how do they relate to ANOVA? / A: ANOVA IS variance decomposition; classical Type I SS is order-dependent; LMG averages over all orderings, mathematically equivalent to Shapley values, satisfies additivity, sums to R². Hier.part gives unique-vs-shared breakdown as a useful supplement.
- Q: Should we include NBA-TV? / A: Exclude — cable specialty channel, pre-selected superfan audience, non-marquee game selection, would confound network effect with consumption-context.
- Q: One prompt is enough to start Claude Code? / A: Yes for Phase 0; but human review is required at every phase boundary.
- Q: When to come back to web chat vs stay in Claude Code? / A: Stay in Claude Code for execution and phase greenlights; return to web chat for unexpected diagnostic failures, results interpretation, paper writing, and AI-evaluation section.
- Q: Git repo workflow? / A: Private repo (licensing); commit raw data + code + writeups + figures + tables + final PDF; ignore installed packages and intermediate data.

### Where the human did NOT intervene

- **Choice of log-transformation for target** — I defaulted to `log(P2+)`; human accepted without discussion
- **Choice of `log1p()` for follower variables** — I made this call to handle zero/low-follower edge cases
- **6-family grouping structure** — I proposed the exact grouping; human didn't challenge it
- **Variable list within each family** — I proposed specific variables (e.g., `last5_win_pct` vs. `last_game_won` vs. `on_fire`); human accepted the full set
- **Decision to drop All-Star Weekend** — I flagged it as a bundled recommendation; human didn't push back
- **Duration filter threshold (60 min)** — I proposed it; human didn't intervene
- **Playoff-stakes categorical structure** (regular / play-in / round1 / round2 / conf_finals / finals) — I designed this; human didn't discuss
- **Bootstrap B = 1000** — I defaulted; human accepted
- **Choice of R project layout and file-naming conventions** — fully AI-driven
- **Decision to include `outputs/session_info.txt` and `renv` pinning** — fully AI-driven (reproducibility hygiene)
- **Paper output structure (Table 1/2/3, Figure 1/2/3)** — I proposed; human accepted

These are places where Claude Code teammates might want to question or stress-test the choice when reviewing the final analysis — the human did not explicitly endorse them, merely didn't object.
