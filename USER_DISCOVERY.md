# User Discovery — The PHP Psychiatrist

> **Status:** Working discovery doc for AgentForge **Stage 4** (Identify Users). This is *not* the final `USERS.md` — it is the researched raw material we review and prioritize before drafting it. Two inputs feed it: (1) domain research on Partial Hospitalization Program (PHP) psychiatry, and (2) a read-only inspection of this fork's actual schema and demo data, so every use case can be grounded in data that exists (or flagged where it doesn't).

---

## 1. The narrowed user

The PRD explicitly rejects "physicians need help finding information," and *"psychiatrist"* alone has the same flaw. Narrowed:

**An attending psychiatrist / medical director of an adult Partial Hospitalization Program (PHP)** — a hospital-level *day* program (patients attend ≥20 hrs/week, ~5–6 hrs/day, 4–5 days/week, and go home at night).

| Attribute | Value | Why it matters for the agent |
|---|---|---|
| Role | Medical director / attending — **owns diagnosis, meds, certification, clinical leadership**. **Not** the group therapist. | The agent's job is **synthesis + triage across a census**, not therapy support. |
| Census | ~12–18 active patients at once *(site-variable, unregulated — flagged)* | Introduces a **cross-patient** dimension absent from the PRD's single-room scenario. |
| Patient contact | Brief **medication-management check-ins ~2–3×/week** per patient (not full sessions) | Each contact is short and high-stakes → pre-encounter catch-up must be fast. |
| Episode | Fixed, goal-driven arc **~2–6 weeks** (commonly ~10–15 program days): admit → daily programming → discharge/step-down | Adds a **longitudinal "are they progressing on the clock?"** dimension. |
| Team | Multidisciplinary (therapists run CBT/DBT/process groups, nurses, social workers) **under physician direction** | Notes accumulate **daily from many authors** → fragmentation is the core tax. |
| Admission pathway | **Step-down** from inpatient, or **step-up** to prevent a hospitalization | Acute population → continuous risk re-assessment is non-negotiable. |
| Regulatory load | CMS requires a **daily physician progress note/patient**; **recert at day 18, then ≤ every 30 days**; commercial UR every 1–2 weeks; **42 CFR Part 2** for SUD/dual-dx | Documentation is **reimbursement-load-bearing**; compliance shapes authorization design. |

**How this maps to the PRD's canonical scenario.** The PRD's "90 seconds between rooms, one patient" moment still exists here (single-patient pre-encounter catch-up). But PHP adds two dimensions the PRD's ED/hospitalist examples lack: a **census** (cross-patient triage) and a **fixed treatment arc** (longitudinal progress vs. discharge goals) — both fed by **multidisciplinary, mostly free-text notes**. That combination is the distinctive, non-generic wedge.

---

## 2. A day in the life — where the agent enters

| Time | What they're doing just before | What they need | What they do with it |
|---|---|---|---|
| **~7:45 AM — pre-programming caseload review** *(flagship moment)* | Facing yesterday's pile of multidisciplinary notes across the whole census | Per-patient synthesis + a ranked **"who needs me most today"** triage | Walks into the day already oriented; plans whom to see first |
| **~8:45 AM — treatment-team rounds prep** | About to run/attend rounds with the team | One-line-per-patient roll-up: arc position, latest scores/trends, open goals, aftercare tasks | Runs efficient rounds; spots step-down readiness |
| **~12:30 PM — mid-day med decision** | A patient isn't responding / reports a side effect | Med history, current regimen, interactions, controlled-substance context, symptom/side-effect trend | Makes a safe on-the-spot titration; documents rationale |
| **End of stay — recert / discharge-readiness** | Day-18 or ≤30-day recert, or a UR call | Full-episode trend vs. goals + medical-necessity evidence + draft aftercare plan | Writes a defensible recert, or executes a clean step-down |

---

## 3. Pain points (grounded, information-centric)

1. **The daily note pile.** Multidisciplinary notes accumulate every day across many staff; the psychiatrist cannot read everything for everyone before programming starts.
2. **Cross-patient triage.** "Who among my census needs me most today?" — the highest-frequency, highest-value question, and there's no single view that answers it.
3. **Fragmentation.** A patient's reality is split across free-text notes, PHQ-9/GAD-7 scores, med lists, group attendance, and risk flags.
4. **Longitudinal arc tracking.** On a 2–6 week clock, *is each patient actually progressing toward discharge goals?* Stalls must be caught early.
5. **Medication management across a census.** Parallel titration, polypharmacy, interactions, controlled substances, extra caution in dual-diagnosis.
6. **Continuous risk re-assessment.** Suicidality/violence signals are often buried in narrative notes or a single PHQ-9 item-9 score.
7. **Documentation is reimbursement-load-bearing.** The recert cadence and the "would need inpatient otherwise" medical-necessity test mean the same trend data serves clinical *and* UR purposes.
8. **Discharge / step-down + aftercare coordination.**

---

## 4. Candidate use cases

Each includes the PRD's required test — **why a *conversational agent* is the right shape** (vs. a dashboard, sorted list, or chart). Strength is my honest read; we prioritize these together in §7.

### UC1 — Morning census triage & synthesis  ⭐ *flagship — Strong*
- **Trigger (~7:45 AM):** psychiatrist opens the co-pilot before programming.
- **Agent does:** reads the last 24h of multidisciplinary notes + score changes + med/risk flags across the census; produces a ranked "who needs me most" list with a one-line *why* per patient, each claim cited.
- **Data:** encounters, group notes, PHQ-9/GAD-7 deltas, meds, `lists` problems, free-text notes.
- **Why an agent:** the naive version is a dashboard — but the value is the **multi-turn drill-down** ("why is Farrah flagged?" → "show the nursing note" → "draft a check-in note") and the fact that triage criteria **change day to day** ("today, who didn't sleep / missed group?"). Natural-language redirection + cited synthesis of **unstructured** text is exactly what a dashboard can't do.

### UC2 — Single-patient pre-encounter catch-up  *(the PRD's 90-second moment — Strong)*
- **Trigger:** 60–90 seconds before a med-management check-in.
- **Agent does:** reconstructs the patient — what changed since last seen, current meds, latest scores/trends, any risk signal — grounded and cited.
- **Data:** one patient's encounters, meds, scores, notes, risk items.
- **Why an agent:** it's inherently **Q&A with follow-ups** ("what's his PHQ-9 trend?", "did he mention SI?", "any med change this week?"). The question set varies per patient and per visit; a fixed chart view forces manual hunting, a conversation surfaces exactly what's asked.

### UC3 — Progress & discharge-readiness review  *(Medium–Strong)*
- **Trigger:** rounds, or when considering step-down to IOP.
- **Agent does:** synthesizes the **full episode** — score trajectories vs. treatment-plan goals, current risk, aftercare readiness — and answers "is X ready to step down, and what's missing?"
- **Data:** `form_treatment_plan` / `form_aftercare_plan` goals, serial scores, encounters, `transfer_summary`.
- **Why an agent:** requires **aggregating across the whole stay and reasoning against criteria**, then iterating ("what's blocking discharge?", "draft the aftercare plan"). Multi-source synthesis + judgment, not a static chart.

### UC4 — Medication decision support  *(High value, Highest risk)*
- **Trigger (~12:30 PM):** non-response or a side effect.
- **Agent does:** chains tool calls — med history, current regimen, allergies, relevant labs, symptom/side-effect trend — and reasons about options/interactions, everything cited.
- **Data:** `prescriptions` + `lists` meds, allergies, `procedure_result`, scores.
- **Why an agent:** genuine **tool-chaining + multi-turn** reasoning. **Caveat:** interaction/dosing claims are the highest hallucination risk in the whole project → verification layer + domain-constraint enforcement are mandatory here (this is where the PRD's "confidently stated hallucination harms a patient" bites hardest).

### UC5 — Continued-stay / recertification evidence drafting  *(Distinctively PHP — Strong, demo-friendly)*
- **Trigger:** day-18 or ≤30-day recert, or a concurrent-review call.
- **Agent does:** assembles episode-long medical-necessity evidence (continued symptoms/risk **and** measurable progress **and** why IOP is premature), grounded in scores/notes, and drafts the recert narrative for physician edit.
- **Data:** serial scores, daily notes, treatment-plan goals, `form_prior_auth`.
- **Why an agent:** it's **grounded generation with iterative refinement** ("emphasize the SI risk", "add the missed-group context") over dozens of records — a form can't write the justification; a conversation can, then let the physician steer it.

### UC6 — Census risk surveillance  *(Medium — partly overlaps UC1)*
- **Trigger:** continuous / on-demand ("any suicidality signals I should know about?").
- **Agent does:** scans PHQ-9 item-9 + narrative mentions of SI/agitation across the census, surfaces + cites.
- **Why an agent:** combines **structured scores + unstructured notes** with cited, natural-language drill-down. **Caveat:** leans alert/dashboard-like; strongest folded into UC1 rather than as a standalone.

---

## 5. Data-grounding map (the reality check)

What each use case needs vs. what this fork actually provides.

| Use case | Data needed | In this fork? | Notes |
|---|---|---|---|
| UC1 Census triage | Encounters, group notes, score deltas, meds, problems, free-text notes | ✅ schema present | Group data via **service/DB layer only** (no FHIR resource) |
| UC2 Catch-up | One patient's meds, scores, notes, risk | ✅ present | REST + FHIR expose meds/conditions/observations/notes |
| UC3 Discharge-readiness | Treatment/aftercare goals, serial scores, transfer summary | ✅ present | `form_treatment_plan`, `form_aftercare_plan` (ASAM dims), `transfer_summary` |
| UC4 Med support | Meds, allergies, labs, scores | ✅ present | Interaction knowledge base is **external** — not in the record |
| UC5 Recert drafting | Serial scores, daily notes, goals, prior-auth | ⚠️ mostly | `form_prior_auth` exists; **no concurrent-review/continued-stay workflow object** |
| UC6 Risk surveillance | PHQ-9 item-9, SI mentions in notes | ⚠️ partial | PHQ-9 `suicide_score` present; **C-SSRS not seeded** |

**Feature inventory (present in fork):** Therapy Groups (`interface/therapy_groups/` + `therapy_groups*` tables + `form_groups_encounter`/`form_group_attendance`); PHQ-9 & GAD-7 forms (`form_phq9` incl. `suicide_score`, `form_gad7`); generic LForms/LOINC questionnaire engine (`questionnaire_repository`/`questionnaire_response` w/ scoring); treatment/aftercare/care/transfer plans; first-class care teams; multidisciplinary note authoring; meds/problems/allergies/labs/vitals/encounters; REST + FHIR R4 (US Core) APIs + `src/Services/` layer, OAuth2/SMART-gated.

*Registration caveat on the table above:* rows relying on `form_phq9` / `form_gad7` / `form_treatment_plan` / `form_aftercare_plan` / `transfer_summary` refer to **installable form modules** (`interface/forms/<name>/table.sql`) — their tables are **not** in `sql/database.sql` and are created only when the form is registered via Administration → Forms. (`therapy_groups*`, `care_team*`, group-encounter forms, and the questionnaire engine *are* installed by default.) Form registration is therefore step 0 of any seeding plan.

### 🚨 Critical gap — no seeded clinical data
The shipped demo (`sql/example_patient_data.sql`) is **14 demographics-only patients — zero meds, diagnoses, notes, scores, or group data**. The *schema* supports every use case above; the *fork ships none of the data*. **Foundational dependency:** before any use case is demonstrable we must load realistic PHP data. Synthea/FHIR import (per `SETUP.md`) gives generic clinical records but **won't produce PHP-specific structures** (therapy-group rosters, serial PHQ-9/GAD-7 series, daily multidisciplinary notes, treatment/aftercare plans) — so **custom seeding is likely required**. This is the single biggest feasibility item and belongs in `USERS.md`'s assumptions and `ARCHITECTURE.md`.

**Other gaps to design around:** C-SSRS not pre-seeded (only PHQ-9 item-9 for suicidality); therapy-group data has no standard FHIR resource (needs service/DB access); no first-class "episode of care / program admission" object (episode boundaries inferred from admit/discharge dates + `therapy_groups_participants` start/end); no concurrent-review UR workflow.

---

## 6. Cross-cutting constraints (tie-back to the PRD's "Hard Problems")

- **Authorization & access control.** The physician's **own census** vs. other patients; **42 CFR Part 2** consent boundaries for SUD/dual-dx data (compliance deadline Feb 16, 2026 — now in effect); enforce via SMART scopes at the data layer, not the prompt.
- **Verification & trust.** Every claim cited to a specific record; domain-constraint enforcement is sharpest in **UC4** (dose thresholds, interactions) and **risk escalation** (PHQ-9 item-9 → surface, never suppress).
- **Speed vs. completeness.** A triage fast-path (UC1) vs. deep synthesis (UC3/UC5); communicate uncertainty when records are incomplete.
- **Failure modes.** Given the data-gap reality, **incomplete/missing records are the expected case, not the edge case** — missing scores, stale notes, empty episodes must degrade gracefully.

---

## 7. Open decisions before drafting `USERS.md`

1. **Primary use-case set.** Recommend **UC1 (census triage)** + **UC2 (single-patient catch-up)** as the non-negotiable core, plus 1–2 of {UC5 recert drafting, UC4 med support, UC3 discharge-readiness}. UC6 folds into UC1.
2. **Population scope.** Default assumption: **adult PHP including a dual-diagnosis share** (realistic; unlocks the compelling 42 CFR Part 2 compliance angle). Overridable to mood/anxiety-only (simpler) or adolescent (different rules).
3. **Data seeding approach.** Default: Synthea import **plus** a custom PHP data-shaping pass (therapy groups, serial scores, daily notes, plans) for 2–3 realistic demo patients. Confirm appetite.

*Assumptions above are defaults I'll use unless you steer otherwise.*

---

### Evidence
- **Fork inspection (local):** `sql/database.sql`, `sql/example_patient_data.sql`, `interface/therapy_groups/`, `interface/forms/{phq9,gad7,treatment_plan,aftercare_plan,prior_auth,newGroupEncounter}/`, `src/Services/`, `apis/routes/`, `SETUP.md`, `API_README.md`, `FHIR_README.md`.
- **Domain research (primary sources):** CMS Medicare Benefit Policy Manual, Pub. 100-02, Ch. 6 (PHP definition, ≥20 hrs/week, step-up/step-down, physician certification, day-18 / ≤30-day recert cadence); CMS PHP LCDs; 42 CFR Part 2 **2024 Final Rule** (effective Apr 16 2024, compliance Feb 16 2026); measurement-based-care literature (PHQ-9/GAD-7/C-SSRS).
