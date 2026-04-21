# Secret Incident Response Runbook

## When Gitleaks detects a secret — step by step

This runbook applies when a secret (API key, password, private key, etc.) is
detected in the repository — whether by Gitleaks, a CI failure, or an external
report.

---

## Severity levels

| Severity | Examples | Response time |
|---|---|---|
| CRITICAL | AWS keys, DB creds, private keys, Stripe live keys | Immediate (< 15 min) |
| HIGH | API tokens, OAuth secrets, Slack webhooks | < 1 hour |
| MEDIUM | Internal tool tokens, staging creds | < 4 hours |

---

## Step 1 — Contain (do this FIRST, before anything else)

**Rotate the secret immediately.** Assume it is already compromised.

Do not wait to investigate whether it was actually accessed. Rotation takes
minutes; a breach investigation takes days.

### AWS credentials
```bash
# Deactivate the exposed key immediately
aws iam update-access-key \
  --access-key-id AKIAEXAMPLE123 \
  --status Inactive

# Create a new key
aws iam create-access-key --user-name your-service-account

# Update the new key everywhere it is used (see Step 3)

# Delete the old key after confirming the new one works
aws iam delete-access-key \
  --access-key-id AKIAEXAMPLE123
```

### Database password
```sql
-- PostgreSQL
ALTER ROLE your_app_user PASSWORD 'new-strong-password-here';

-- MySQL
ALTER USER 'your_app_user'@'%' IDENTIFIED BY 'new-strong-password-here';
```

### GitHub Personal Access Token
1. Go to GitHub → Settings → Developer settings → Personal access tokens
2. Delete the exposed token immediately
3. Create a new one with the minimum required scopes

### Stripe API key
1. Log in to Stripe Dashboard → Developers → API Keys
2. Roll the key (this immediately invalidates the old one)

### Generic API key
Log in to the issuing platform and regenerate/rotate the key. Every major
platform (SendGrid, Twilio, Slack, etc.) has a key management page.

---

## Step 2 — Remove from Git history

> ⚠️ Rewriting history affects everyone. Coordinate with your team first.

### Option A — BFG Repo Cleaner (recommended, faster)
```bash
# Install BFG
brew install bfg   # macOS
# or download from: https://rtyp.io/bfg

# Clone a fresh copy
git clone --mirror https://github.com/your-org/your-repo.git repo.git
cd repo.git

# Replace all occurrences of the secret string with REMOVED
echo 'AKIAEXPOSEDKEYHERE' > ../secrets-to-remove.txt
bfg --replace-text ../secrets-to-remove.txt

# Clean up and force-push
git reflog expire --expire=now --all
git gc --prune=now --aggressive
git push --force
```

### Option B — git filter-repo (modern, built-in)
```bash
pip install git-filter-repo

# Remove a specific file that contained the secret
git filter-repo --path path/to/secret-file.env --invert-paths

# Or replace a literal string in all files
git filter-repo --replace-text <(echo 'AKIAEXPOSEDKEY==>REMOVED')

git push --force --all
git push --force --tags
```

After force-pushing:
- Ask all team members to re-clone (not pull — re-clone)
- Invalidate any cached clones in CI/CD systems

---

## Step 3 — Update the secret everywhere it is used

Go through every place the old secret was deployed:

- [ ] CI/CD pipeline secrets (GitHub Actions, GitLab CI, CircleCI, etc.)
- [ ] Production environment variables (ECS task definitions, K8s secrets, etc.)
- [ ] Staging environment variables
- [ ] Developer `.env` files (notify all team members)
- [ ] Secrets manager (AWS Secrets Manager, HashiCorp Vault, GCP Secret Manager)
- [ ] Any third-party integrations that use the key

---

## Step 4 — Investigate exposure

Check whether the secret was actually used maliciously:

### AWS — check CloudTrail
```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=AccessKeyId,AttributeValue=AKIAEXPOSEDKEY \
  --start-time "2024-01-01T00:00:00Z" \
  --max-results 50
```

### GitHub — check audit log
Go to: `https://github.com/organizations/YOUR-ORG/settings/audit-log`
Filter by the token or user.

### Database — check query logs
Review your DB slow query log or audit log for unusual queries.

---

## Step 5 — Post-incident

1. **Write a brief incident report** (even one paragraph) — what was exposed,
   when it was committed, when detected, what action was taken.
2. **Add to allowlist if it was a false positive** — update `.gitleaks.toml`
   with a targeted allowlist rule so it does not re-trigger.
3. **Review why the hook was bypassed** — was `--no-verify` used? Was the
   developer missing the pre-commit setup? Fix the root cause.

---

## False positive handling

If Gitleaks flags a non-secret (e.g. a test fixture, example value, or
documentation snippet):

1. **Do not use `--no-verify` to bypass.** This skips ALL hooks.
2. Add a targeted allowlist to `.gitleaks.toml`:

```toml
[[rules]]
id = "your-existing-rule-id"
# ... keep the rule as-is, add this block:

  [rules.allowlist]
  regexes = ['''the-specific-safe-string''']
  # OR limit to specific paths:
  paths   = ['''tests/fixtures/example_config\.yaml''']
  # OR add an inline comment to the line in question:
  # gitleaks:allow
```

3. You can also add an inline annotation to a specific line:
   ```python
   EXAMPLE_KEY = "AKIAIOSFODNN7EXAMPLE"  # gitleaks:allow
   ```

4. Open a PR with the allowlist change — get it reviewed before merging.

---

## Secrets management — do this right from the start

| Use case | Recommended approach |
|---|---|
| Local dev | `.env` file (gitignored) + `.env.example` template |
| CI/CD | GitHub Actions encrypted secrets (`Settings → Secrets`) |
| Production | AWS Secrets Manager / GCP Secret Manager / HashiCorp Vault |
| Short-lived cloud auth | OIDC federation (no static keys at all) |
| Shared team secrets | Password manager with team sharing (1Password Teams, Bitwarden) |

Never store secrets in:
- Source code (any language)
- `docker-compose.yml` (use `.env` file or Docker secrets)
- Kubernetes manifests (use Kubernetes Secrets or External Secrets Operator)
- GitHub wiki or issues
- Slack messages or email
