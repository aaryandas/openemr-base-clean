# API Contracts — Clinical Co-Pilot Dataflow

Companion to [`ARCHITECTURE.md`](./ARCHITECTURE.md) (§2.3 request lifecycle, §3.4 contracts-as-source-of-truth). Every edge of the agent's dataflow is a typed contract defined here. **Each contract was checked against the actual schema** (`sql/database.sql`, `interface/forms/*/table.sql`) and the existing code paths — grounding notes and feasibility caveats are attached where the schema forced a design change.

Conventions: contracts are the source of truth (Pydantic on the sidecar, mirrored JSON Schema for the PHP Gateway and the Bruno collection). All timestamps ISO-8601. All IDs are integers unless noted.

---

## 0. Cross-cutting rules (apply to every edge)

- **Auth:** every Gateway call carries `Authorization: Bearer <SMART token>` with scope `user/copilot.read`, minted by OpenEMR's existing OAuth2/OIDC server (`src/Common/Auth/OpenIDConnect`) on behalf of the logged-in clinician. *Feasibility (verified in code): the scope string must satisfy `ScopeEntity::createFromString`'s `context/resource.permission` grammar — a bare `copilot.read` is rejected as invalid format — and is registered via a listener on `RestApiScopeEvent::EVENT_TYPE_GET_SUPPORTED_SCOPES` (`ScopeRepository::getCurrentSmartScopes`). New scope + client on the existing auth server; no new server.*
- **Correlation:** `X-Correlation-Id` (UUIDv4, minted by the sidecar per invocation, = OTel trace ID) is **required** on every Gateway request; requests without it are rejected 400. It is stamped into every log line, SQL comment, disclosure record, LLM span, and the final response.
- **Error envelope (all endpoints):**
  ```json
  { "error": { "code": "out_of_census | restricted | upstream_timeout | invalid_request | internal",
               "correlation_id": "…" } }
  ```
  Never an exception message. *Grounding: `apis/dispatch.php:42` currently returns raw `$e->getMessage()` (audit SEC-4) — the Gateway controller catches everything itself so nothing reaches that handler.*
- **Row caps:** every list-returning endpoint has a server-side hard cap (default 50, max 200) independent of what the client asks for, and reports `truncated: true` when hit. *Grounding: `QueryPagination::DEFAULT_LIMIT = 0` means the existing search stack emits NO `LIMIT` when unspecified (PERF-2) — the Gateway must not reuse it.*

### Shared types

```python
class RecordRef(BaseModel):          # the citation primitive — names a real row
    table: Literal["patient_data","lists","prescriptions","form_encounter",
                   "forms","form_phq9","form_gad7","form_clinical_notes",
                   "form_soap","form_dictation","form_treatment_plan",
                   "form_aftercare_plan","therapy_groups_participants"]
    id: int                          # the row's primary key
    uuid: str | None = None          # binary(16) uuid where the table has one (nullable — DQ-11)

class DataCaveat(BaseModel):         # machine-readable "what's missing/suspect"
    code: Literal["missing_field","zero_date_scrubbed","possible_duplicate_chart",
                  "uncoded_entry","row_cap_hit","null_uuid_rows","orphan_rows",
                  "restricted_content_withheld","incomplete_instrument","dual_source_conflict"]
    detail: str                      # human-readable, no PHI values
    refs: list[RecordRef] = []

class RiskFlag(BaseModel):
    type: Literal["phq9_item9","si_mention"]     # C-SSRS not seeded (USERS.md) — item-9 is the signal
    value: int | None                # item-9: 0–3
    date: datetime
    source: RecordRef
```

---

## Edge 1 — Chat panel → Sidecar

```
POST /chat                         (sidecar, Python)
```
```python
class ChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=2000)
    thread_id: UUID | None           # continue a conversation; None = new thread
    patient_ctx: PatientContext | None   # {pid: int>0} when the panel has a chart open
    stream: bool = True
```
Auth: the SMART Bearer token from the panel's OAuth authorization-code grant. The sidecar validates signature/expiry/scope against OpenEMR's JWKS, then forwards the token on every Gateway call (the Gateway — not the sidecar — decides authorization). `thread_id`s are bound to the token subject — a thread can only be resumed by the clinician who started it.

## Edge 8 — Sidecar → Chat panel (response)

```python
class ChatResponse(BaseModel):
    thread_id: UUID
    correlation_id: UUID
    status: Literal["ok","fallback","refused"]   # fallback = verification failed / tool down; refused = authz
    answer: str                                   # rendered from verified claims only
    citations: list[RecordRef]                    # union of claim source_ids
    verification: VerificationResult              # edge 7 object, returned for transparency
    caveats: list[DataCaveat]                     # surfaced, not hidden (speed-vs-completeness rule)
```

---

## Edge 2 — Sidecar → Gateway (the six read tools)

All under `/apis/<site>/copilot/…` (PHP, `src/Services` side). Responses are `{data: …, caveats: [DataCaveat], truncated: bool}`.

### `GET /copilot/census`
```python
class CensusEntry(BaseModel):
    pid: int
    name: str
    last_24h: Activity24h            # {new_notes: int, score_events: int, med_events: int}
    risk_flags: list[RiskFlag]
    sources: list[RecordRef]
```
**Grounding / feasibility.** "Own census" resolves as the union of, in authority order: `care_teams(pid, status='active') ⋈ care_team_member(user_id=clinician, status='active')` (both tables exist with usable keys), `form_encounter.provider_id = clinician`, and `therapy_groups_counselors(user_id) ⋈ therapy_groups_participants(group_id, status)`. Care team is authoritative because the persona doesn't run groups (she may appear in zero `therapy_groups_counselors` rows). `provider_id = 0` is a "no provider" sentinel (DQ-8) — excluded explicitly.

### `GET /copilot/patients/{pid}/summary`
```python
class PatientSummary(BaseModel):
    pid: int
    as_of: datetime
    demographics: Demographics       # name, dob: date|None, sex: str|None  ('' → None per DQ-1)
    problems: list[Problem]          # lists WHERE type='medical_problem' AND activity=1  (DQ-5)
    allergies: list[Allergy]         # lists WHERE type='allergy' AND activity=1
    active_medications: list[Medication]
    latest_scores: dict[Literal["phq9","gad7"], ScorePoint | None]  # None = "not on file", stated
    risk_flags: list[RiskFlag]
    recent_encounters: list[EncounterRef]   # form_encounter: id, date, reason, class_code
    caveats: list[DataCaveat]
    sources: list[RecordRef]

class Problem(BaseModel):
    title: str
    code: CodedValue | None          # parsed from lists.diagnosis "SYSTEM:code"; None ⇒ caveat uncoded_entry
    onset: date | None               # begdate; '0000-00-00' → None + zero_date_scrubbed caveat (DQ-2)
    source: RecordRef

class Medication(BaseModel):
    drug: str                        # prescriptions.drug varchar(150) — free text
    rxnorm: str | None               # rxnorm_drugcode, nullable ⇒ uncoded_entry caveat (DQ-6)
    dosage: str | None; route: str | None
    start: date | None; active: bool # prescriptions.active (int, default 1)
    source: RecordRef
```
**Grounding / feasibility.** Projected columns only — never `SELECT *` on the ~132-column `patient_data` (PERF-10), never `ss` (CMP-8). Medications have **two source tables** (`prescriptions` and `lists type='medication'`); the Gateway reads both and emits a `dual_source_conflict` caveat when they disagree, rather than silently preferring one. `dupscore > threshold` ⇒ `possible_duplicate_chart` caveat (DQ-3).

### `GET /copilot/patients/{pid}/notes?query=&since=&limit=`
```python
class NoteExcerpt(BaseModel):
    excerpt: str = Field(max_length=500)
    date: datetime | None
    author: Author                   # user_id: int|None, display: str  — see caveat below
    note_type: Literal["clinical_note","soap","dictation","group_note"]
    encounter: int | None
    source: RecordRef
```
**Grounding / feasibility.** Notes live in `form_clinical_notes` (has `description`, `clinical_notes_type/category`, `activity`), `form_soap`, `form_dictation`, `form_groups_encounter` — all reached through the `forms` registry (`formdir`, `form_id`, `pid`, `encounter`, **`deleted = 0` filter is mandatory**). Author attribution: `forms.user` is a **username string** and `users.username` has no UNIQUE constraint (DQ-4) — the contract exposes `user_id` when resolvable via `forms.provider_id ≠ 0`, else `display` with a caveat. Search is `LIKE`-based at MVP (no FTS index exists); contract is stable if FTS is added later.

### `GET /copilot/patients/{pid}/scores/{instrument}`  (`phq9 | gad7`)
```python
class ScorePoint(BaseModel):
    date: datetime | None
    total: int | None                # 0–27 (PHQ-9) / 0–21 (GAD-7); None if any item non-numeric
    item9: int | None                # PHQ-9 only: suicide_score 0–3 — drives RiskFlag
    incomplete: bool                 # True ⇒ caveat incomplete_instrument
    source: RecordRef                # {table: form_phq9, id}
class ScoreSeries(BaseModel):
    instrument: Literal["phq9","gad7"]
    points: list[ScorePoint]         # ascending by date
    severity_bands: str              # version tag of the band table verification checks against
```
**Grounding / feasibility — this contract was reshaped by the schema.** `form_phq9`/`form_gad7` have **no total column and no encounter column**, and every item score is `varchar(255)` (verified in `interface/forms/*/table.sql`). So: the Gateway computes `total` by casting the 9 (resp. 7) item columns, returns `total=None, incomplete=True` when any item is non-numeric/empty, links to encounters via `forms` (`formdir='phq9'`, `form_id`, `deleted=0`), and filters `activity=1`. Item-9 = `suicide_score`, cast 0–3. **These tables don't exist until the forms are registered** (not in `database.sql`, not in the default registry) — form registration is step 1 of data seeding.

### `GET /copilot/patients/{pid}/episode`
```python
class Episode(BaseModel):
    admit_date: date | None              # form_aftercare_plan.admit_date / therapy_groups_participants.group_patient_start
    discharge_date: date | None          # form_aftercare_plan.discharged; None = still active
    program_membership: list[Membership] # therapy_groups_participants: group_id, status, start, end
    treatment_plan: PlanDoc | None
    aftercare_plan: PlanDoc | None
class PlanDoc(BaseModel):
    date: datetime | None
    sections: list[PlanSection]          # {name: str, text: str} — free text, verbatim
    source: RecordRef
```
**Grounding / feasibility — honest downgrade forced by the schema.** An earlier sketch (`get_episode_goals`) implied structured goals with status; the schema says otherwise (and `ARCHITECTURE.md §2.2` now reflects this): `form_treatment_plan` is free-text blobs (`presenting_issues`, `diagnosis`, `treatment_received`, `recommendation_for_follow_up`); `form_aftercare_plan` has ASAM-dimension **text** fields plus real `admit_date`/`discharged` dates. So the contract exposes **named free-text sections**, "goals met?" is LLM reasoning *over cited section text* (never a computed boolean), and UC3's readiness verdict must carry its evidence as citations into those sections. There is no episode-of-care object (USERS.md assumption confirmed) — episode boundaries are inferred exactly as declared.

---

## Edge 3 — Gateway → MySQL (internal, but contract-relevant)

Not an API, but the diagram edge is governed by rules the contracts above depend on: one query per section with `WHERE pid IN (…)` + `LIMIT <cap>`; authors/facilities resolved once per request via `IN (…)` (kills PERF-1/6/7/9); `forms.deleted = 0`; `lists.activity = 1` unless status explicitly carried; normalization at the read edge (`'' → NULL`, `0000-00-00 → NULL` + caveat). Every emitted row becomes a `RecordRef` — this is what makes Edge 6's source binding checkable.

---

## Edge 4 — Sidecar → Gateway → `extended_log` (disclosure, fail-closed)

```
POST /copilot/disclosures
```
```python
class DisclosureCreate(BaseModel):
    correlation_id: UUID
    pid: int
    purpose: Literal["uc1_triage","uc2_catchup","uc3_discharge"]
    field_scope: list[str]           # field/section NAMES only — never values (CMP-5)
    recipient: str                   # e.g. "anthropic:claude-sonnet"
class DisclosureReceipt(BaseModel):
    disclosure_id: int               # extended_log.id
```
**Rule the whole system hangs on:** the sidecar may not call the LLM without a `disclosure_id` for this `correlation_id` + `pid`. Write failure ⇒ egress halts (`status="fallback"`), alert fires. In a multi-step agent turn the rule applies **per tool result that enters a prompt** — a UC1 census turn writes one row per patient whose data reaches the model (§164.528 accounting is per patient), and drill-down reads write additional rows with the expanded `field_scope`. Writes are **idempotent on (`correlation_id`, `pid`, hash(`field_scope`))** so repair/network retries of the same LLM call cannot double-count a disclosure.
**Grounding / feasibility.** `extended_log` exists (`date, event, user, recipient, description longtext, patient_id`) and `EventAuditLogger::recordDisclosure()` already writes it — the Gateway reuses the table with `event='llm-disclosure'` and a JSON `description` `{correlation_id, purpose, field_scope}`. Two schema gaps, handled: no `correlation_id` column (JSON in `description` now; an indexed column is a cheap later migration) and no immutability (tamper-evidence comes from the HMAC/hash-chain audit work, CMP-3). The dedicated event type is deliberately **not** routed through `auditSQLEvent`'s heuristic, so the `audit_events_*` toggles can't disable it (CMP-2/4).

---

## Edges 5 & 6 — Sidecar ↔ Claude

**Edge 5 (out): minimum-necessary prompt.** The payload is exactly the Gateway projections for this turn (plus conversation messages) — enforced structurally because the sidecar has nothing else: it holds no DB access and no raw FHIR (trust boundary, not convention). `ss` is never in any projection; `field_scope` of the disclosure record matches the projection fields sent.

**Edge 6 (back): structured output, not prose.**
```python
class Claim(BaseModel):
    text: str
    source_ids: list[RecordRef] = Field(min_length=1)   # ≥1 or the claim cannot be stated as fact
class AgentDraft(BaseModel):
    claims: list[Claim]
    caveats_acknowledged: list[str]   # caveat codes the model saw and must reflect
```
**Feasibility.** Claude structured outputs / tool-use JSON conforms to this schema reliably; `RecordRef`s are echoes of IDs the Gateway issued this turn, so verification is set-membership, not NLP. Malformed output ⇒ Pydantic rejection ⇒ one repair retry ⇒ fallback (Edge 8 `status="fallback"`).

---

## Edge 7 — Verification gate (internal contract)

```python
class VerificationResult(BaseModel):
    passed: bool
    checks_run: list[str]
    failed: list[FailedCheck]        # {check, claim_index, reason}
    # checks: source_binding        — every Claim.source_ids ⊆ records retrieved under this correlation_id
    #         severity_band         — stated PHQ-9/GAD-7 severity matches cited total (bands versioned)
    #         active_medication     — meds stated as current have active=1 / activity=1
    #         item9_surfaced        — if any retrieved ScorePoint.item9 > 0, the answer must surface it
    #         caveats_honored       — caveat codes present ⇒ reflected, not contradicted
```
Fail ⇒ `ChatResponse.status="fallback"` with what's missing; the draft is never delivered. Pass/fail rate is a dashboard metric and an alert.

---

## Edge 9 — Everything → Langfuse (observability)

OTel spans; `trace_id = correlation_id`. Span attributes contract: `tool`, `duration_ms`, `status`, `tokens_in/out`, `cost_usd`, `verify.passed`, `disclosure_id`, `truncated`. The Gateway propagates the header so PHP-side timings join the same trace. **PHI stance — two rules for two records** (per `ARCHITECTURE.md §8`): traces deliberately carry PHI-bearing payloads (that's what makes a wrong clinical answer debuggable) and are confined to self-hosted, access-controlled, retention-capped Langfuse inside the trust zone; **audit and disclosure rows** follow the opposite rule — field names/scope only, never values (CMP-5/SEC-7). This is what makes "reconstruct any request from logs alone" literally true, disclosure record included.

### Sidecar health surface
`GET /health` → `{status:"ok"}` (process only). `GET /ready` → 200/503 with `{checks: {gateway, claude, langfuse}}` — each an actual probe (scoped test read / models ping / ingest reachable), per the engineering requirement.

---

## Feasibility findings summary (what the code review changed)

| # | Finding (verified in schema/code) | Contract consequence |
|---|---|---|
| 1 | `form_phq9`/`form_gad7`: per-item `varchar` scores, **no total, no encounter column**; linkage only via `forms` registry | Gateway computes totals; `incomplete` flag; joins through `forms` with `deleted=0`; `item9` explicit field |
| 2 | PHQ-9/GAD-7/treatment/aftercare/transfer **form tables don't exist until forms are registered** (not in default registry) | Form registration is seeding step 1; `/ready` test read fails loudly, not silently, if missing |
| 3 | `form_treatment_plan` = free-text sections, **no structured goals/status** | `Episode` exposes `PlanSection{name,text}`; readiness is cited reasoning, never a computed boolean |
| 4 | `extended_log` has no correlation/scope columns | `correlation_id` + `field_scope` as JSON in `description`; later migration optional; fail-closed enforced app-side via required `disclosure_id` |
| 5 | Census joins exist and are indexed: `care_teams`+`care_team_member`, `therapy_groups_participants(group_id,pid)`, `form_encounter.provider_id` | Census = care-team (authoritative) ∪ provider ∪ group-counselor; `provider_id=0` sentinel excluded |
| 6 | Meds in **two tables** (`prescriptions`, `lists type='medication'`); codes optional | Read both; `dual_source_conflict` caveat; `rxnorm: None` ⇒ `uncoded_entry` |
| 7 | `lists.activity` nullable; FHIR Condition path doesn't filter it (DQ-5) | Contracts hard-default `activity=1`; status never inferred from absence |
| 8 | Existing pagination defaults to **unlimited** (`DEFAULT_LIMIT=0`, PERF-2/3) | Gateway caps server-side; `truncated` flag is part of every list contract |
| 9 | Dispatcher leaks exception messages (SEC-4); reflective CORS (SEC-2) | Error envelope with `correlation_id` only; Gateway sets its own strict CORS/no-CORS headers |
| 10 | `users.username` non-unique; `forms.user` is a username string (DQ-4) | `Author.user_id` preferred via `provider_id≠0`; username-only attribution carries a caveat |

**Why these contracts are effective for the defense:** every PRD requirement that sounded abstract now has a field: *source attribution* = `Claim.source_ids: min_length=1` over Gateway-issued `RecordRef`s; *minimum necessary* = the projection **is** the prompt; *fail-closed disclosure* = `disclosure_id` as a precondition in the type system; *graceful degradation* = `status`, `truncated`, and `DataCaveat` are response fields, not log lines; *correlation* = one UUID that is simultaneously the trace ID, the log key, and a disclosure-record field.
