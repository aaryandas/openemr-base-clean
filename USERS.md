# USERS.md — Target User, Workflow & Use Cases

> **AgentForge Stage 4 deliverable.** This document is the **source of truth** the agent's architecture traces back to. Every capability built in Stage 5+ must point to a use case here; anything that points to no use case should not be built.
>
> *Filename note: the PRD's Stage 4 hard gate specifies `./USERS.md`; the submission table calls it `./USER.md`. This file is canonical; a pointer file [`USER.md`](./USER.md) ships alongside it so both spellings resolve.*

---

## Summary

The Clinical Co-Pilot serves **one** user: the attending psychiatrist who is the **medical director of an adult Partial Hospitalization Program (PHP)** — a hospital-level *day* program (patients attend ≥20 hrs/week and go home at night). This user is not a generic "physician." They carry a live **census of ~12–18 patients at once**, see each for a brief **medication-management check-in ~2–3×/week** (they do *not* run the group therapy), and move each patient along a **fixed 2–6 week treatment arc** toward step-down. Their day is fed by a **daily pile of free-text notes from many disciplines** (therapists, nurses, social workers), and their documentation is **reimbursement-load-bearing** (recertification cadence, medical-necessity tests). The population includes **dual-diagnosis** patients, so **42 CFR Part 2** consent boundaries are in scope.

Their dominant problem is **information synthesis under time pressure across a census** — not looking up one fact about one patient, but answering *"who among my patients needs me most today, why, and what changed?"* and *"is this patient ready to step down, and if not, what's missing?"* The agent addresses three use cases at the three decision points of a PHP episode:

| # | Use case | Moment | Decision it supports |
|---|---|---|---|
| **UC1** | **Census triage & synthesis** | ~7:45 AM, before programming | Whom to see first today, and why |
| **UC2** | **Single-patient pre-encounter catch-up** | 60–90 s before each med check | What to address in this specific visit |
| **UC3** | **Discharge-readiness review** | Rounds / step-down consideration | Whether a patient can move down the ladder |

Each is defended below as a task the user would genuinely choose a **conversational agent** for — over a dashboard, a sorted list, or a better chart.

---

## 1. The target user

**Persona (illustrative composite):** *Dr. Maya Okafor*, attending psychiatrist and medical director of a **16-seat adult PHP** at a community behavioral-health hospital.

| Attribute | Detail | Consequence for the agent |
|---|---|---|
| **Role** | Medical director / attending. Owns diagnosis, the medication plan, certification, and clinical leadership. **Therapists run the groups — she does not.** | The agent's value is **synthesis + triage across a census**, not therapy content or scheduling. |
| **Census** | ~12–18 active patients simultaneously. | Introduces a **cross-patient** dimension the PRD's single-room scenario lacks. |
| **Patient contact** | Brief **med-management check-ins ~2–3×/week** per patient (minutes, not a full session). | Pre-encounter prep must resolve in **seconds**. |
| **Episode** | Fixed, goal-driven **~2–6 week** arc (≈10–15 program days): admit → daily programming → step-down/discharge. | Adds a **longitudinal "on-track vs. stalled?"** dimension. |
| **Team & data** | Multidisciplinary notes accumulate **daily** from many authors, mostly **free text**. | The core data is **unstructured**; fragmentation is the central tax. |
| **Acuity** | Patients are here as a **step-down from inpatient** or **step-up to avoid admission**. | **Continuous suicide/violence risk re-assessment** is non-negotiable. |
| **Population** | Adult, **including dual-diagnosis** (co-occurring substance use disorder). | **42 CFR Part 2** consent boundaries constrain what the agent may reveal and to whom. |
| **Regulatory load** | CMS: **daily physician progress note** per patient; **recert at ~day 18, then ≤ every 30 days**; commercial UR every 1–2 weeks. | Documentation drives reimbursement; trend data serves clinical *and* UR purposes. |

### Who this agent is explicitly *not* for (scope guardrails)
- **Not the group therapist / other disciplines.** The agent is scoped to the attending's med-management and clinical-leadership workflow, not group facilitation, nursing tasks, or scheduling.
- **Not a generic medical chatbot.** It answers questions about *this program's patients from their records*, not open-domain medical trivia.
- **Not patient-facing.** No patient or family ever talks to it.
- **Not an autonomous clinician.** It informs the psychiatrist's decisions; it never prescribes, discharges, or acts on its own.

---

## 2. The workflow — where the agent enters the day

A PHP episode has a repeating daily rhythm and a longer arc. The agent enters at three points:

1. **~7:45 AM — pre-programming caseload review.** Before patients arrive, Dr. Okafor faces yesterday's accumulated notes across all ~16 patients. In the 30 seconds before she opens the co-pilot she's holding coffee and a vague memory of who was struggling. She needs to walk into the day **already oriented and triaged** → *UC1*.
2. **Throughout the morning — brief med checks.** Between programming blocks she pulls patients for 3–5 minute medication check-ins. In the 60–90 seconds before each, she needs **this patient reconstructed** → *UC2*.
3. **Rounds & across the stay — step-down decisions.** In team rounds, and whenever an authorization window is closing, she must judge **who is ready to move down the ladder** → *UC3*.

---

## 3. Use cases

Each use case states the moment, what the user needs, the data the agent reads (grounded in this fork), **why a conversational agent is the right shape**, the guardrails it must honor, and what "useful" means.

### UC1 — Census triage & synthesis  ⭐ *flagship*

**Moment.** ~7:45 AM. *"Between 7:45 and 8:00, tell me what changed for each patient overnight/yesterday and who I need to see first."*

**What she's doing 30 s before.** Arriving, no chart open, unsure which of 16 patients are stable and which slipped.

**What the agent does.** Retrieves the active census, then for each patient synthesizes the last 24 hours — new multidisciplinary notes, PHQ-9/GAD-7 changes, medication events, group attendance, and any risk signal — and returns a **ranked "who needs you most" briefing** with a one-line *why* per patient, every claim cited to its record.

**Data it reads (fork-grounded).** Census/roster via `care_teams`/`care_team_member` (authoritative — the attending doesn't run groups), plus `form_encounter` provider assignment and `therapy_groups_participants` (services/DB layer); free-text notes via the `forms` registry → `form_soap` / `form_clinical_notes` / `form_dictation`; scores via `form_phq9` (incl. `suicide_score`) / `form_gad7`; meds via `prescriptions` + `lists`; group notes via `form_groups_encounter` / `form_group_attendance`.

**Why a conversational agent (not a dashboard / sorted list).**
- The ranking is a judgment over **unstructured free text from many authors** — "what matters today" can't be expressed as structured filters on a dashboard. It requires reading and weighing salience.
- **The triage lens changes daily.** Some mornings the question is "who's a safety risk," others "who's disengaging from groups," "who's due for a med decision," "who's near discharge." A conversation lets her state today's lens in words; a dashboard would need a pre-built widget for every possible lens.
- The briefing is a **launchpad for multi-turn drill-down** — "why is bed 4 flagged?" → "show me the nursing note" → "what's his PHQ-9 trend?" — with context carried across turns. A dashboard makes her click and re-orient at every step.
- It is inherently **tool-chaining**: roster → per-patient retrieval across several sources → synthesis. That is agent-shaped work.

**Guardrails / refusals.** Only patients on *her* census. Every flagged item cited; nothing asserted that isn't in the record. Suicidality signals (PHQ-9 item 9, SI mentions in notes) are **always surfaced, never summarized away**. Part 2–protected SUD content is withheld if her access scope doesn't cover it.

**"Useful" =** she walks into programming with an accurate, cited, correctly-ordered picture and sees her top-priority patients first — without having opened a single chart.

---

### UC2 — Single-patient pre-encounter catch-up

**Moment.** 60–90 seconds before a med-management check-in. *"Catch me up on Eduardo before I bring him in."*

**What she's doing 30 s before.** About to call a patient from the milieu; remembers the name, not the week's detail.

**What the agent does.** Reconstructs one patient on demand — what changed since she last saw him, current regimen and any recent changes, latest scores and their trend, and any active risk flag — and then answers **follow-ups** ("did he report side effects?", "what did the SW note say about housing?", "any missed groups?"), all grounded and cited.

**Data it reads (fork-grounded).** One patient's `form_encounter` + notes, `prescriptions`/`lists` meds and allergies, `form_phq9`/`form_gad7` series, `procedure_result` labs, risk items — reachable via REST/FHIR (`Patient`, `Encounter`, `MedicationRequest`, `Condition`, `Observation`, `QuestionnaireResponse`) and the services layer.

**Why a conversational agent (not a fixed summary card).**
- The needed facts **vary per patient and per visit** — a static card must guess; a conversation answers exactly what she asks and supports "and what about…?" chains within her time budget.
- With ~60 seconds, **asking in natural language beats navigating chart tabs**. She can't afford to hunt.
- Grounding + citation lets her **trust and verify in the same breath**, which a raw chart view doesn't.

**Guardrails / refusals.** Same authorization and citation rules as UC1. If a record is thin (e.g., no note since admission), the agent **says what's missing** rather than inventing continuity. No open-domain medical advice untethered from this patient's data.

**"Useful" =** she starts the check-in already knowing the one or two things that matter, and can chase a specific worry without breaking eye contact with the chart for 90 seconds.

---

### UC3 — Discharge-readiness review

**Moment.** Team rounds, or when an authorization window is closing. *"Is Nora ready to step down to IOP — and if not, what's blocking it?"*

**What she's doing 30 s before.** Weighing a step-down decision she'll have to justify to the team and the payer.

**What the agent does.** Reasons across the **whole episode** — score trajectories vs. the treatment-plan goals, current risk level, and whether aftercare is arranged — and returns a **structured readiness assessment**: a verdict, the supporting evidence (cited), and a specific list of **what's still blocking discharge**. She can then iterate: "what's the aftercare gap?", "summarize the case for rounds."

**Data it reads (fork-grounded).** `form_treatment_plan` / `form_aftercare_plan` (ASAM-style goals) and `transfer_summary`; serial `form_phq9`/`form_gad7`; `form_encounter` history; `care_teams`/`care_team_member` for aftercare ownership.

**Why a conversational agent (not a scores chart).**
- Readiness is a **multi-factor judgment** — trajectory *and* goals met *and* risk low *and* aftercare arranged. A chart of PHQ-9 scores shows one axis; it can't weigh the four together or articulate a defensible conclusion.
- The decision is **deliberative and contestable**, which is exactly where multi-turn helps: "is she ready?" → "what's blocking it?" → "is the follow-up appointment booked?" → "draft the rounds summary."
- It requires **episode-wide aggregation across several forms** (tool-chaining), then reasoning against criteria — agent-shaped, not chart-shaped.

**Guardrails / refusals.** The agent **never decides discharge** — it structures evidence for the physician. It states readiness **with uncertainty** and flags missing inputs (e.g., "no C-SSRS on file; only PHQ-9 item 9 available"). Citations required for every supporting claim.

**"Useful" =** she can defend a step-down (or a continued stay) to the team and the payer in one minute, with the blocking items named and evidence attached.

---

## 4. What the use cases demand of the architecture

These requirements are the bridge to `ARCHITECTURE.md`. Each maps to a PRD "Hard Problem."

- **Authorization & access control.** All three use cases are scoped to the physician's **own census**, and the dual-diagnosis population means **42 CFR Part 2** SUD content must be gated by consent scope. Enforcement belongs at the **data/service layer** (SMART-on-FHIR scopes), never in the prompt. *MVP posture (OpenEMR has no consent object): sensitivity-flagged encounters are withheld entirely; consent-based release is roadmap — see `ARCHITECTURE.md §4.2`.*
- **Verification & trust.** Every surfaced claim must be **attributable to a specific record** (UC1/UC2/UC3), and risk signals must be **escalated, never suppressed** (UC1/UC3). Score interpretation (PHQ-9/GAD-7 severity bands) is a domain constraint the agent must apply correctly.
- **Speed vs. completeness.** UC1 (triage) and UC2 (catch-up) are **latency-critical** (a morning briefing and a 60-second lookup); UC3 tolerates more latency for deeper synthesis. The agent needs a fast path and a deep path.
- **Failure modes.** Given the data reality (below), **incomplete/missing records are the expected case** — thin notes, absent scores, no aftercare yet. The agent must degrade gracefully and **name what's missing** rather than fabricate.

### Capability → use-case trace (the PRD's core constraint)

Every capability below exists because a use case needs it; capabilities with no use case are **deliberately not built**.

| Capability | Required by | Why it's needed |
|---|---|---|
| Multi-turn conversation | UC1, UC2, UC3 | Drill-down (census→patient→action), per-visit follow-ups, readiness deliberation |
| Tool chaining / multi-step retrieval | UC1, UC3 | Roster→per-patient synthesis; episode-wide aggregation across forms |
| Synthesis over unstructured notes | UC1, UC2, UC3 | The daily multidisciplinary note pile is the core data source |
| Source attribution / citations | UC1, UC2, UC3 | Verification & trust; nothing asserted without a record |
| Risk-signal escalation + score interpretation | UC1, UC3 | Surface suicidality; apply PHQ-9/GAD-7 severity bands |
| Authorization scoping (own census + Part 2) | UC1, UC2, UC3 | Multi-user clinical setting; SUD consent boundaries |
| Structured output (ranked roster, readiness verdict) | UC1, UC3 | The briefing and the readiness assessment have defined shapes |

**Not building (no use case requires it):** autonomous prescribing or a drug-interaction engine (that was the deferred UC4), open-domain medical Q&A, chart write-back/automation, patient-facing chat, scheduling.

---

## 5. Assumptions & dependencies

- **Illustrative persona.** "Dr. Okafor" and the 16-seat program are a composite; the *type* of user is the real target.
- **🚨 Data-seeding dependency (foundational).** This fork ships **demographics-only demo data** (14 patients; zero meds, diagnoses, notes, or scores). None of these use cases is demonstrable until realistic PHP data is loaded. **Step 0 is form registration:** the five behavioral-health forms (`phq9`, `gad7`, `treatment_plan`, `aftercare_plan`, `transfer_summary`) are installable modules whose tables are *not in the default schema* — they are created when the form is registered via Administration → Forms. Then: **Synthea/FHIR import** for baseline clinical records **plus a custom PHP-shaping pass** (therapy-group rosters, serial PHQ-9/GAD-7, daily multidisciplinary notes, treatment/aftercare plans) for a handful of demo patients, plus a small **deliberately-broken tier** for eval boundary cases. This is the single biggest feasibility item and is carried into `ARCHITECTURE.md §14`.
- **C-SSRS not seeded.** Suicide-risk signal is limited to **PHQ-9 item 9** out of the box; a fuller C-SSRS could be loaded later via the LForms/LOINC questionnaire engine.
- **Therapy-group data is not exposed via FHIR.** Census/roster retrieval (UC1) uses the **services/DB layer**, not standard FHIR resources.
- **No first-class "episode of care" object.** Episode boundaries (UC3) are **inferred** from admit/discharge dates on treatment/aftercare forms and `therapy_groups_participants` start/end.

## 6. Deliberately deferred (and why)

The PRD rewards *fewer but defensible* capabilities. Deferred, with rationale:

- **UC4 — Medication decision support.** Highest clinical value but highest hallucination risk; revisit once the verification layer is proven on UC1–UC3.
- **UC5 — Recert / UR drafting.** Valuable and distinctively PHP, but generation-heavy; a strong week-2 addition once episode-synthesis (UC3) exists.
- **UC6 — Census risk surveillance.** Folded into **UC1** rather than built standalone; the morning triage already surfaces suicidality signals.
