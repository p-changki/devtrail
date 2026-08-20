---
name: devtrail-qa-check
description: Build a reproducible manual QA checklist and file every failure as a troubleshooting note.
triggers:
  - "QA check"
  - "checklist"
  - "/devtrail-qa-check"
user_invocable: true
---

# QA checklist

Check by hand, without automation — but write it so it is **reproducible**.

## 🔑 Failures go into the vault

The original only printed results. **A failure that is not recorded will trip
you in the same place again.**

```bash
devtrail path trouble    # failures go here
```

Passes are fine on screen. **Only failures become notes.**

## Scenario shape

Write each item like this.

```
### <scenario name>
- Preconditions:
- Steps:
    1.
    2.
- Expected:
- Actual:
- Verdict: ✅ Pass / ❌ Fail
```

**Someone else must be able to follow the steps exactly.** Not "log in", but
"log in at the login page with test@example.com / password".

## Handling failures

When something fails, create a troubleshooting note using
`$(devtrail path templates)/Troubleshooting.md`.

| Severity | Bar |
|---|---|
| Critical | Data loss · security · total outage |
| High | A core feature does not work |
| Medium | A defect with a workaround |
| Low | Wording · minor annoyance |

**Critical and High get a cause hypothesis too.** Symptoms alone mean
investigating again later.

## Do not

- Mark something Pass that you did not check — write "not run" instead
- Fix things automatically — QA is observation; fixing is separate work
- Inflate severity

## Report

```
8 scenarios · ✅ 6 · ❌ 2 · ⏭ not run 0

❌ High   No redirect after login → Troubleshooting/2026-08-20 login redirect.md
❌ Low    Typo in a button label
```
