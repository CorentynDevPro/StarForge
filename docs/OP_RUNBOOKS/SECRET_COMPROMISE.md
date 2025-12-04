# Runbook — Secret Compromise / Credential Leak

---

## Purpose

Immediate, actionable runbook for handling suspected or confirmed compromise of secrets, credentials, `API` keys,
tokens, or other sensitive material used by StarForge. This document provides containment, rotation, verification,
forensic and communication steps to recover safely and minimise impact.

---

## Audience

- `SRE` / `Platform engineers`
- `Security engineers`
- `Backend engineers` owning affected services
- `Incident commander` and `on-call responders`

---

## Scope

- Any secret leakage (private key, service account, DB credentials, `API` key, `GitHub secret`, `OAuth client secret`).
- Both accidental exposures (committed to repo, pasted to public chat) and confirmed malicious exfiltration.
- Covers cloud provider credentials, database credentials, message broker/Redis, Sentry/observability tokens, and
  third-party API keys.

---

## Principles

- Assume compromise until proven otherwise.
- Rotate/revoke compromised secrets immediately — do not wait for full investigation.
- Preserve evidence for forensic analysis (capture logs, snapshots) before wide destructive actions.
- Minimise blast radius: isolate affected systems and temporarily stop services that rely on compromised secrets if
  needed.
- Communicate proactively with stakeholders (product/support/legal) and follow escalation paths.

---

## Immediate actions (first 5–15 minutes)

1. Acknowledge and create an incident channel (e.g. `#incident-secret-<ts>`).
2. Identify the secret(s) suspected or confirmed compromised and scope of exposure (repository, pastebin, Slack, error
   logs).
3. Containment (fast, non-destructive):
    - Remove public exposure (delete gist, remove message, take down page) — preserve a copy for `forensics`.
    - If secret exists in a repository commit, do NOT rebase force-push to hide it; follow Git leak process (see
      `Forensics`).
4. Rotate/revoke the secret immediately:
    - Issue a revocation in the provider console (`AWS keys`, `Google service account keys`, `Sentry token`,
      `Stripe API key`, etc.).
    - Replace with a new secret stored securely (`Secrets Manager` / `Vault` / `GitHub Actions secrets`) and deploy
      minimal changes that use it.
5. Pause services if necessary:
    - If the compromised secret grants write access (DB, `S3`, payment provider), consider pausing ingestion/jobs or
      scaling down workers temporarily to prevent abuse.
6. Record actions: who performed rotations, timestamps, new secret IDs, and any provider request IDs.

---

## Containment & rotation checklist

- [ ] Identify affected secret name(s), type, and usage.
- [ ] Revoke compromised secret/token immediately in provider's console or UI.
- [ ] Generate new credential(s) and store them in the secrets store (`HashiCorp Vault` / `AWS Secrets Manager` /
  `GitHub Actions Secrets`).
- [ ] Update dependent services/configs to use the new secrets (deploy a targeted update).
- [ ] Rotate all secrets with the same scope or standing permissions (e.g., if one `AWS` access key leaked, rotate all
  access/secret keys for that `IAM` user).
- [ ] Revoke any idle or older keys belonging to same account that could be abused.
- [ ] If credentials allow creation of further keys (service account), rotate service account keys and audit created
  keys.

---

## Provider-specific rotation notes (examples)

- `AWS Access Key`
    - Console: `IAM` → Users → Security credentials → Create access key → update clients → deactivate old key → delete
      old key.
    - If root keys leaked: rotate root key immediately and prefer to delete root keys — create an admin `IAM` user and
      use it.

- `Google Service Account key`
    - Console: IAM & Admin → Service Accounts → Keys → Delete compromised key → create new key → update secrets.

- `GitHub Personal Access Token` (`PAT`) or `App Key`
    - Revoke token in GitHub settings immediately and check audit logs. Replace tokens used by `CI` and dev machines.

- Database credentials
    - Create new DB user credential with same privileges or rotate password for existing user.
    - Update application secrets and restart app workers sequentially to apply new credentials.

- `Supabase` / managed `Postgres`
    - Rotate DB password via provider UI and update `DATABASE_URL` in secrets store; ensure apps reboot with new
      credentials.

- `Redis` / Message broker secrets
    - Rotate `AUTH tokens` or `ACL` users; for `Redis Auth`, set a new password and update clients.

- Third-party `API` Keys (`Stripe`, `Sendgrid`, `Sentry`, etc.)
    - Revoke `API` key in provider dashboard and create a new one; update application secrets.

---

## Forensics & evidence preservation

Do these before destructive changes when feasible (but do not delay critical rotations):

1. Preserve evidence
    - Save copies of exposed secret artifacts (file, gist URL, chat message) to secure forensic storage (`S3` with
      limited access).
    - Timestamp and record who saved it.

2. Gather logs
    - Collect access logs for services using the compromised secret: Cloud provider console logs (`CloudTrail`), DB
      audit logs, application logs, and network logs.
    - Query for suspicious activity from the time of exposure to present (e.g., unusual `API` calls, large downloads,
      creation of new keys).

3. Snapshot infrastructure state
    - Take snapshots where possible (DB snapshot, disk snapshot) if there is potential data destruction risk.

4. Git exposure specific steps
    - If secret was committed: do NOT force-push to hide it. Use the GitHub secret scanning and follow the repo-specific
      remediation. GitHub offers secret scanning and token revocation suggestions.
    - Record the commit `SHA`, file path, and revisions for the forensic record.

---

## Investigation & scope analysis (next 1–4 hours)

- Query `CloudTrail` (`AWS`) / `Audit Logs` (`GCP`) for actions by the principal tied to the leaked credentials.
- Identify resources accessed: list buckets, DB connections, `API` calls, or tokens issued.
- Determine timeframe of abuse and enumerate data impacted (read, write, delete).
- If financial providers involved (`Stripe`, `PayPal`), check for fraudulent charges and escalate to Legal/Finance.

---

## Service recovery & redeployment

1. Deploy updates using the new secrets:
    - Use canary deployment: update a single pod/instance and verify behavior.
    - Monitor logs and metrics closely for abnormal activity (errors, spikes).

2. Re-enable paused services gradually:
    - Bring back workers incrementally and monitor for suspicious behaviour.

3. Verify access controls:
    - Ensure rotated credentials do not inadvertently grant broader permissions than intended.
    - Apply the last privilege to new secrets.

---

## Communication & escalation

- Internal: Post initial incident note in incident channel with summary:
    - What leaked, when discovered, initial containment actions, owners, and next steps.
- Stakeholders: Notify Product, Support, Legal, Finance (if payments), and Privacy/Compliance if user data may be
  impacted.
- External disclosure: Coordinate with Legal/Compliance for any external notifications if required by law or provider
  contracts.
- Craft short public message for status page or customer support if impact can affect users (avoid revealing detailed
  technical info).

---

## Suggested incident status template

### Initial:

```
Incident: suspected credential compromise detected at <time>.
Affected secret(s): <type/name>.
Containment actions: secret revoked/rotated, services paused (if applicable).
Owner: @<oncall>.
Next update: in 30 minutes.
```

### Investigation update:

```
Investigation: access logs indicate <actions> by principal <id> between <time> - <time>.
Data impacted: <buckets / DB tables>.
Remediation: rotated keys, revoked tokens, deployed patched config to services.
ETA for complete remediation: <time>.
```

---

## Verification & validation (post-remediation)

- Confirm revoked key no longer works (attempt to use revoked token should fail).
- Verify new keys are being used by all services and no service is still using the old secret.
- Scan repository and recent logs to ensure the secret is fully removed from code and CI history.
- Monitor for re-use attempts or suspicious activity for at least `7–30 days` depending on severity.

---

## Detection hardening & prevention (post-incident)

- Enable and enforce secret scanning in GitHub (and other `SCM`).
- Enforce branch protection and require secrets to be stored in Secrets Manager, not code.
- Integrate pre-commit hooks (git-secrets) and `CI` scanning.
- Rotate long-lived credentials to short-lived tokens where possible (`AWS STS`, `GCP` short-lived keys).
- Add alerting for unusual resource activity (`CloudTrail` anomalous events, sudden data egress).
- Centralise secrets in `Vault / Secrets Manager` and restrict access via `IAM` roles.
- Educate developers on secure handling of secrets and leak reporting process.

---

## Audit & reporting

- Produce incident report with timeline, actions, evidence, scope of data accessed, and remediation.
- Attach logs, snapshots, commit SHAs, and rotated key IDs.
- Track follow-up tasks: rotate other related keys, update runbooks, add tests/preflight checks.

---

## Useful commands & snippets

```bash
-- AWS: list access keys for a user
aws iam list-access-keys --user-name <username>

-- AWS: deactivate an access key
aws iam update-access-key --user-name <username> --access-key-id <AKIA...> --status Inactive

-- GCP: delete a service account key
gcloud iam service-accounts keys delete <key-id> --iam-account=<service-account-email>

-- GitHub: revoke a PAT (UI) or OAuth app (UI); check audit log for token use (org admins).

-- Example: rotate DB password (Postgres)
psql -c "ALTER USER deployer WITH PASSWORD '<new_password>';"
# Update secrets store and restart services using the new DATABASE_URL
```

---

## Related runbooks & docs

- [docs/OP_RUNBOOKS/DB_RESTORE.md](./DB_RESTORE.md) — database restore runbook
- [docs/OP_RUNBOOKS/DB_CONNECTION_EXHAUST.md](./DB_CONNECTION_EXHAUST.md) — DB connection exhaustion
- [docs/OP_RUNBOOKS/APPLY_MIGRATIONS.md](./APPLY_MIGRATIONS.md) — migration apply runbook
- [docs/OBSERVABILITY.md](../OBSERVABILITY.md) — monitoring and alerting guidance
- [docs/MIGRATIONS.md](../MIGRATIONS.md) — migration practices (backup before migrations)

---
