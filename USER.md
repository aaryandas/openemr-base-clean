# USER.md → canonical document: [USERS.md](./USERS.md)

The PRD names this deliverable `USER.md` in the submission table and `USERS.md` in the
Stage-4 hard gate. **[USERS.md](./USERS.md) is the canonical document**; this pointer
exists so both spellings resolve. Summary of what it defines:

**Target user (one, deliberately narrow):** the attending psychiatrist / medical
director of an adult **Partial Hospitalization Program (PHP)** — a ~12–18 patient
census, brief med-management check-ins 2–3×/week per patient, a fixed 2–6 week
treatment arc, a day fed by free-text multidisciplinary notes, CMS recertification
cadence, and a dual-diagnosis population (42 CFR Part 2 in scope).

**Use cases (each defended as agent-shaped, not dashboard-shaped):**

| # | Use case | Moment | Decision it supports |
|---|---|---|---|
| **UC1** | Census triage & synthesis | ~7:45 AM, before programming | Whom to see first today, and why |
| **UC2** | Single-patient pre-encounter catch-up | 60–90 s before each med check | What to address in this specific visit |
| **UC3** | Discharge-readiness review | Rounds / step-down consideration | Whether a patient can move down the ladder |

Full personas, workflow walkthroughs, per-use-case "why an agent" defenses, guardrails,
capability-to-use-case trace, and assumptions: **[USERS.md](./USERS.md)**.
