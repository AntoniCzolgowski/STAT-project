# NBA National TV Ratings and AI-Assisted Modeling

This repository contains a STAT 5010 final project on NBA national television ratings and the role of AI in a data science workflow. The project studies nationally televised NBA games and asks which pregame factors help explain audience delivery: star power, market size, team form, matchup quality, playoff stakes, network/distribution, and timing.

The business motivation comes from sports media advertising. National TV inventory is often sold before games air using guaranteed audience estimates. If a game underdelivers, the seller may owe makegood inventory. Better estimates can therefore help both media vendors and advertisers price and plan live sports campaigns more effectively.

The project was also designed around the course's AI-for-data-science theme. Claude was used for planning, R coding, diagnostics, model implementation, and phase writeups. The final report evaluates not only the statistical results, but also where AI helped, where it made questionable choices, and where human domain judgment changed the analysis.

## Research Question

**Among nationally televised NBA games, which pregame factors most strongly predict variation in total and key-demo audience delivery?**

The implemented analysis treats that question mainly as an explanatory driver-decomposition problem. A log-linear regression model is fit for national audience size, then model fit is decomposed across predictor families using LMG variance decomposition, an order-averaged approach closely related to Shapley-value attribution.

## Main Findings

In the full sample, the largest source of explained variation is postseason context. The initial family decomposition labeled this as part of "Matchup," but the final report critiques that interpretation: most of the signal comes from playoff stage, not ordinary matchup attractiveness.

Network/distribution is the next-largest contributor, followed by timing factors such as day, holiday, and broadcast slot. In the regular-season-only model, the story changes: network and timing dominate, while star power becomes a more meaningful secondary driver. Market size and recent team form are statistically detectable but small relative to the larger broadcast and scheduling effects.

The final report emphasizes an important limitation: this is stronger as an interpretable explanatory analysis than as a production forecasting system. A real audience-estimation tool would need temporal train/test validation and out-of-sample performance checks.

## Method Summary

- Cleaned and deduplicated national NBA telecast ratings.
- Matched games to schedule, team, market, and player/team followership features.
- Engineered predictor families:
  - Star power
  - Market size
  - Team form
  - Matchup quality / playoff stakes
  - Network / distribution
  - Timing
- Fit log-linear regression models for national audience size.
- Used HC3 robust standard errors for coefficient inference.
- Used LMG decomposition with bootstrap confidence intervals to estimate each family's share of explained variance.
- Ran robustness checks using alternative targets, sample restrictions, and regular-season-only models.
- Documented human review, AI assumptions, model critiques, and code-audit notes across phase writeups and the final report.

## Repository Structure

```text
R/          Analysis scripts, ordered by project phase
writeups/   Phase-by-phase notes and human/AI collaboration logs
outputs/    Generated tables and figures used in the final report
data/raw/   Placeholder only; confidential raw data is not tracked
```

The raw data used for the analysis is confidential and intentionally excluded from the public repository. The `data/raw/.keep` file preserves the expected folder structure for local use.

## Key Outputs

Important generated artifacts live in `outputs/`:

- `outputs/figures/fig2_family_lmg.png`: headline full-sample driver decomposition
- `outputs/figures/fig5_regular_season.png`: regular-season-only decomposition
- `outputs/tables/tbl2_regression_coefficients.csv`: main regression coefficients
- `outputs/tables/tbl3_robustness.csv`: robustness comparison
- `outputs/tables/tbl4_regular_season.csv`: regular-season-only results

The phase writeups in `writeups/` document assumptions, modeling decisions, diagnostics, risks, and human review throughout the workflow.

## AI Evaluation Takeaways

The final report concludes that AI was very effective at quickly producing a clean, organized, and reproducible analysis pipeline. It handled data cleaning, feature engineering, regression modeling, diagnostics, visualization, and documentation at a high level.

The report also identifies several limitations. The AI answered the original explanatory question but did not independently push toward the more useful business question of forecasting future games. It also leaned heavily on the preplanned predictor-family structure, which made the full-sample "matchup" result less intuitive until humans asked for a regular-season-only model. The project therefore argues that AI can accelerate data science work, but human analysts still need to define the useful question, audit assumptions, and connect statistical output to domain reality.

## Reproducibility Note

The scripts are organized to be run in phase order from the `R/` directory. Because the raw data is not included, the full pipeline will only reproduce on a machine that has the required confidential source files available locally under `data/raw/`.

## Authors

STAT 5010 final project by Creager, Czolgowski, and Goodell.
