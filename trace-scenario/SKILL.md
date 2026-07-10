---
name: trace-scenario
description: Trace a real user or system scenario end-to-end through a named environment, using project wiring to inspect services, logs, queues, APIs, and databases, then write an evidence dossier for an ExecPlan Discovery section. Use when planning depends on empirical behavior, database truth, or cross-service data flow evidence rather than code inspection alone.
---

# Trace Scenario

Trace a concrete scenario through the live system environment named by the
operator. The output is evidence for planning, not an implementation change.

## Inputs

Require both:

- Scenario: the exact user action, job, API call, import, export, or workflow to
  trace.
- Environment: the operator-named target such as local, dev, staging, preview,
  or another project-defined environment.

If either input is missing, ask for it before touching systems. Do not infer an
environment from the branch, host, prompt wording, or credentials.

## Workflow

1. Confirm scope.
   - State the scenario and named environment.
   - Identify whether the trace can be read-only. If any step would mutate data,
     send traffic, enqueue work, replay a job, or alter state, stop and ask for
     explicit authorization before that step.

2. Discover project wiring.
   - Read project `AGENTS.md`, `.agent/`, `.codex/`, docs, runbooks, scripts,
     service manifests, env examples, and test fixtures that describe
     environments, DBs, services, queues, logs, and external dependencies.
   - Treat environment names, credentials, hosts, and access methods as
     project-scoped. This root skill does not restrict or invent them.

3. Map expected hops before querying.
   - List each service, store, queue/topic, scheduled job, external dependency,
     and observed artifact that should participate.
   - For every database, identify schema or collection names, owner/service,
     likely readers, likely writers, and the safest read-only query path.

4. Collect evidence hop by hop.
   - Prefer read-only commands, bounded log reads, request traces, metrics,
     existing local/dev/test data, and SELECT-style DB queries.
   - Record exact commands or tool calls, timestamps, environment, sanitized
     identifiers, row counts, key field values, and relevant log snippets.
   - Do not print secrets or unnecessary PII. Use stable non-PII IDs when
     possible.

5. Reconcile observed behavior.
   - Compare expected hops with observed evidence.
   - Mark each hop as observed, missing, ambiguous, or not inspected.
   - Separate evidence from inference. If a conclusion depends on inference,
     say what evidence supports it and what could disprove it.

6. Write the dossier.
   - Create `.agent/infra/` if the project has no stricter location.
   - Write `.agent/infra/YYYY-MM-DD-<scenario-slug>-<environment>-trace.md`.
   - Use the local current date for `YYYY-MM-DD`.

## Dossier Shape

````markdown
# <Scenario> Trace - <Environment>

## Summary
- Scenario:
- Environment:
- Trace window:
- Result:

## Project Wiring Used
- <paths, scripts, docs, env commands, connection names>

## Hop Map
| Hop | Component | Expected role | Evidence | Status |
| --- | --- | --- | --- | --- |

## Database Evidence
| Store | Schema/table/collection | Owner | Readers | Writers | Query/evidence | Finding |
| --- | --- | --- | --- | --- | --- | --- |

## Commands And Observations
```text
<bounded commands, timestamps, outputs, and notes>
```

## Open Questions And Risks
- <unknowns, missing access, ambiguous evidence, safety risks>

## ExecPlan Discovery Bullets
- <facts ready to paste into an ExecPlan Discovery section>
````

## Safety Rules

- Stay within the operator-named environment.
- Do not use production credentials or data unless the operator explicitly names
  production as the environment and authorizes the access.
- Do not mutate data, replay jobs, send customer-visible traffic, or trigger
  side effects without explicit authorization.
- If only production could answer the question and production is not authorized,
  state that limitation in the dossier.
