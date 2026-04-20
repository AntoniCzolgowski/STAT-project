# Phase 7 — Robustness / sensitivity analysis

## Purpose

Stress-test the Phase 5 headline decomposition by re-running family-level
LMG under four alternative specifications. Per §7 and §11 of the plan,
this is where we check whether the Matchup-dominant, Network-second,
everything-else-small story survives plausible perturbations of the
target variable, the sample, and the model.

## Inputs / Outputs

**Inputs**
- `data/processed/primary_model.rds` (from Phase 4)
- `data/processed/model_data.rds`
- `data/interim/phase5_lmg_results.rds` (for sensitivities A, C, which are reused)

**Outputs**
- `data/interim/phase7_robustness.rds` — full bundle
- `outputs/tables/tbl_robustness_family.csv` — family LMG × 5 sensitivities
- `outputs/figures/fig_robustness.png` — dodged bar chart comparing all five

## Sensitivities

| ID | Target | Sample | Extra term | n | R² | Boot reps |
|---|---|---|---|---:|---:|---:|
| **A** (reference) | log(P2+) | full | — | 573 | 0.866 | 1000 |
| **B** | log(P18-49) | full | — | 573 | 0.835 | 500 |
| **C** | log(P2+) | pre-2025/26 | — | 452 | 0.889 | 1000 |
| **D** | log(P2+) | full, drop top-10 Cook's D | — | 563 | 0.891 | 500 |
| **E** | log(P2+) | full | + `post_new_deal` | 573 | 0.867 | 500 |

A and C come from the Phase 5 bundle (1000 reps). B, D, E are new and
use 500 reps to keep runtime down — precision is still ample for the
comparisons being made here.

## Key results — family LMG across sensitivities

| Family | A: ref | B: P18-49 | C: pre-25/26 | D: drop top-10 | E: + new_deal |
|---|---:|---:|---:|---:|---:|
| **Matchup** | 60.1% | 66.3% | 66.0% | 62.5% | 58.6% |
| **Network** | 16.5% | 9.6% | 12.6% | 16.3% | 15.9% |
| **Timing** | 6.7% | 4.1% | 6.4% | 7.2% | 6.8% |
| **Star power** | 1.7% | 1.8% | 1.8% | 1.5% | 1.7% |
| **Team form** | 1.0% | 1.0% | 1.4% | 1.0% | 1.0% |
| **Market size** | 0.7% | 0.7% | 0.8% | 0.6% | 0.7% |
| `post_new_deal` | — | — | — | — | 1.9% |

(Full table with 95% bootstrap CIs in `outputs/tables/tbl_robustness_family.csv`;
see `outputs/figures/fig_robustness.png` for the CI whiskers.)

## What the sensitivities say

- **The ordering is invariant.** Across every spec, the ranking is
  Matchup ≫ Network > Timing > Star power ≈ Team form ≈ Market size.
  Nothing about that ordering depends on the target variable, the
  sample window, or the handling of influential games.

- **Matchup is structurally dominant; influential games don't drive
  it (D).** Dropping the 10 most-influential games moves Matchup only
  from 60.1% → 62.5%, while overall R² rises from 0.866 to 0.891 (the
  dropped rows had large residuals, not large matchup-driven fits).
  The qualitative story is unchanged.

- **Network absorbs a younger-demo premium less well (B).** For P18-49,
  Network drops from 16.5% → 9.6% and Matchup rises to 66.3%. Reading:
  young viewers are *more* matchup-driven and *less* network-loyal
  than the all-ages P2+ audience, which is consistent with the general
  cord-cutting story for 18-49s.

- **Pre-2025/26 (C) and adding `post_new_deal` (E) both partially
  un-confound Network from the 2025/26 rights deal.** In C, Network
  falls 16.5% → 12.6% simply by removing the year where NBC/Peacock
  entered. In E, adding `post_new_deal` as its own term gives it 1.9%
  of R², and Network shrinks only marginally (16.5% → 15.9%) —
  meaning the 2025/26 effect is mostly absorbed *through* the
  network identity itself (NBC / Peacock / ESPN–ABC as the new deal's
  carriers), not through a separate "post-deal era" lift. The
  `post_new_deal` coefficient is β = 0.067 (+6.9% on P2+), 95% CI
  (−0.003, 0.136) — borderline, which is exactly what you'd expect
  for a variable that is almost collinear with the new network levels.

- **The three small families (Star power, Team form, Market size) are
  small everywhere.** Each holds 0.6–1.8% of R² across all five specs
  with tight CIs. These aren't drivers.

## Decisions

- Sensitivity D was originally specified as "drop Cook's D > 4/n" (36
  rows). That threshold leaves a design where sparse factor cells
  (NBC = 12 games, Prime = 25 games) shrink enough that `relaimpo`'s
  covariance-matrix check fails with "not positive definite." The
  `lm()` itself is fine — no aliasing — but LMG via `calc.relimp`
  can't run on it. I changed D to drop the top-10 most-influential
  games instead. This answers the same qualitative question ("does the
  story survive if we remove the most extreme games?") while keeping
  conditioning healthy. Documented in-script and here.
- B, D, E use 500 bootstrap reps vs 1000 for A, C. Runtime reason only;
  CI widths are already small enough that doubling reps wouldn't move
  the qualitative comparison.

## Assumptions

- The primary spec's formula (log response, log1p-followers, etc.) is
  appropriate for P18-49 as well as P2+. The residual diagnostics from
  Phase 4 are P2+-specific; for B, R² = 0.835 is materially lower, which
  is expected for a narrower demo but we did not separately check its
  diagnostics.
- `post_new_deal` is a reasonable one-variable stand-in for the
  2025/26 rights era. It doesn't capture within-deal heterogeneity
  (e.g., NBC Peacock-streamed vs NBC-broadcast games), and by
  construction it's nearly collinear with the new network identities.

## Alternatives considered

- **Full Cook's D > 4/n drop (36 rows):** rejected above; replaced with
  top-10 drop.
- **HC3-weighted LMG:** `relaimpo` doesn't support heteroscedasticity-
  robust LMG out of the box; the decomposition is fundamentally about
  partitioning R² so the robust-SE machinery doesn't naturally plug
  in. Skipped. HC3 is already applied to coefficient inference in
  Phase 5/Phase 4.
- **Log(P25-54) as third demo:** would be redundant with B and the
  plan only requires one alternative target.

## Risks

- **Borderline CI on `post_new_deal` (E).** The (−0.003, 0.136) CI just
  crosses zero. With one more season of data the sign would likely
  settle; for now, the decomposition result (1.9% of R²) is the more
  stable statement than the coefficient p-value.
- **500 vs 1000 boot reps.** The CI widths visibly widen slightly in
  B/D/E vs A/C — this is expected and honest. No qualitative conclusion
  hinges on a CI boundary that differs between 500 and 1000 reps.
- **Small-cell factor levels still sparse in D.** Even after dropping
  only 10 rows, NBC and Prime remain small cells; the LMG point
  estimate for Network in D is essentially identical to A (16.3% vs
  16.5%), which is reassuring, but one should not over-interpret
  Network changes of a few percentage points between specs.

## Human collab log

- Decomposition ordering holds across all five specs → the headline
  Phase 5 finding is robust.
- Sensitivity D's threshold was changed from ">4/n" to "top-10" due
  to a `relaimpo` numerical issue; acknowledged and explained here
  rather than re-engineered, per project norm on small-sample
  pragmatism.
