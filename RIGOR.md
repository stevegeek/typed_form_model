# Who made this, and how carefully

*A [Rigor, Vouch, Stages](https://rigor.diaconou.com/) disclosure stamp. The format and vocabulary are specified at [rigor.diaconou.com/spec](https://rigor.diaconou.com/spec/), version 1.0.*

<!-- rigor:summary -->
**The idea was mine. Before LLMs, the plan was mine; the implementation was
written by me; it was reviewed for quality and tested, both by me. Since LLMs,
the plan has been reworked by me with an AI; the implementation has been
reworked by an AI, and it has been reviewed for quality and for security, and
tested, all by an AI. Nothing has needed changing lately; I still use this and
would respond if it broke. The project is still evolving. I have read and
understood this code; I can explain every line of it. This assessment is as of
2026-09-04. I make no recommendation either way about depending on it. Why: it
is young, extracted only in 2026. Statement made by: Stephen Ierodiaconou.**
<!-- /rigor:summary -->

## Notes

typed_form_model provides typed Rails form objects on top of Literal::Struct and
ActiveModel. Like typed_operation, it has lived in my client work since 2018 in
several forms, by hand and before LLMs. The extraction into a gem, in 2026, was
AI-led: the plan was reworked with an AI, and the implementation, the reviews
and the tests since then are the AI's work under my direction. I have read the
extracted code and can explain it.

It is young, so I make no recommendation either way. Nothing has needed changing
since the extraction, and it is not finished: `activity: dormant`, `scope:
evolving`.

## Stamp

```yaml
spec: "1.0"
signed: "Stephen Ierodiaconou"
rigor: comprehended
vouch: {claim: neutral, why: "it is young, extracted only in 2026"}
checks:
  comprehended: [human, human-with-ai]
  quality_reviewed: [human, ai]
  security_reviewed: ai
  tested: [human, ai]
stages:
  idea: {by: human}
  plan: {by: [human, human-with-ai]}
  implementation: {by: [human, ai]}
  maintenance: {by: human-with-ai, activity: dormant, scope: evolving}
assessed: 2026-09-04
```

<!--
checks: surface any subset; a done value names who did it.
  comprehended / quality_reviewed / security_reviewed / tested / owned:
    yes | human | ai | human-with-ai | no | not-applicable,
    or a pair [before LLMs, since LLMs] of actors.
  engineered and owned must surface the checks they imply; comprehended
  cannot be satisfied by an AI alone.
Run `rigor-md fmt RIGOR.md` after editing the stamp to refresh the summary.
-->