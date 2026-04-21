# Secret Management Guide

This document covers how secrets are managed in this repository and what every
developer needs to know.

---

## First-time setup (required for all developers)

```bash
# Clone the repo, then run the installer
git clone https://github.com/your-org/your-repo.git
cd your-repo
chmod +x scripts/install-hooks.sh
./scripts/install-hooks.sh
```

This installs Gitleaks and the pre-commit framework so secrets are caught
before they ever leave your machine.

---

## Local development — `.env` files

Use the `.env.example` file as a template:

```bash
# Copy the template
cp .env.example .env

# Fill in your real values — this file is gitignored
nano .env
```

The `.env` file is listed in `.gitignore` and will never be committed.
The `.env.example` file contains only placeholder values and is safe to commit.

**Never do this:**
```bash
# BAD — hard-codes a secret in source
DATABASE_URL=postgresql://app:realpassword@db.prod.example.com/mydb
```

**Do this instead:**
```python
# Python
import os
db_url = os.getenv("DATABASE_URL")

# Node.js
const dbUrl = process.env.DATABASE_URL;

# Go
dbUrl := os.Getenv("DATABASE_URL")
```

---

## CI/CD secrets

All secrets used in GitHub Actions must be stored as **GitHub Actions Secrets**
(repository or organisation level):

- Go to `Settings → Secrets and variables → Actions`
- Add secrets there — they are encrypted at rest and masked in logs
- Reference them in workflows as `${{ secrets.MY_SECRET }}`

**For cloud authentication, use OIDC instead of static keys.** The deploy
workflow is pre-configured for AWS OIDC. This means no `AWS_ACCESS_KEY_ID` or
`AWS_SECRET_ACCESS_KEY` is stored anywhere.

---

## Production secrets

| Service | Where secrets live |
|---|---|
| AWS | AWS Secrets Manager or Parameter Store |
| GCP | GCP Secret Manager |
| Azure | Azure Key Vault |
| Self-hosted | HashiCorp Vault |
| K8s | External Secrets Operator pulling from the above |

Application code should fetch secrets at startup from the secrets manager, not
read them from environment variables baked into the container image.

---

## Branch protection — what's enforced

The `main` branch has these rules set in GitHub:

- Direct push is blocked — all changes go through PRs
- The `gitleaks-diff-scan` check must pass before merge is allowed
- At least one review is required
- Linear history is enforced (squash or rebase only)

To configure these rules yourself: `Settings → Branches → Add rule → main`

---

## What happens if Gitleaks fires?

### Pre-commit (local)
Your commit is blocked. You will see output like:
```
Finding:     aws_access_key_id = "AKIAIOSFODNN7EXAMPLE"
Secret:      AKIAIOSFODNN7EXAMPLE
RuleID:      aws-access-key-id
Entropy:     3.87
File:        config/settings.py
Line:        14
Commit:      0000000000000000000000000000000000000000
```

**Fix:**
1. Remove the secret from the file
2. Move it to `.env` (which is gitignored)
3. Reference it via environment variable in code
4. Try committing again

### GitHub Actions (CI)
The workflow fails with a red ✗. The PR cannot be merged until it is fixed.

**Fix:** Same as above — remove the secret, push the fix, the workflow re-runs.

### False positive?
If the finding is not a real secret (a test fixture, example value, etc.):
1. Add an allowlist entry to `.gitleaks.toml` (see the allowlist section)
2. Or annotate the specific line: `# gitleaks:allow`
3. Open a PR with the change — do NOT use `git commit --no-verify`

---

## Using `--no-verify`

`git commit --no-verify` skips all local hooks. **Do not use it.** The reason:

1. The GitHub Actions workflow will catch the secret anyway and fail the PR
2. If you somehow merge with a secret, it is now in the public git history
3. You will need to rotate the credential and rewrite history — painful

If the hook is blocking you for a legitimate reason, fix the root cause:
- Real secret → move to `.env` or secrets manager
- False positive → add an allowlist entry to `.gitleaks.toml`
- Broken hook → raise it with the team, fix the hook

---

## GitHub Advanced Security (GHAS) — push protection

If your organisation has GitHub Advanced Security enabled, GitHub's own secret
scanning adds a third layer on top of Gitleaks:

- Detects secrets at push time (before they land in the remote)
- Covers 200+ secret types from GitHub's own patterns
- Alerts repository admins when a known pattern is found

To enable: `Settings → Code security → Secret scanning → Enable`

For push protection (blocks the push before it reaches GitHub):
`Settings → Code security → Secret scanning → Push protection → Enable`

---

## Checklist for new services / integrations

When adding a new third-party service to the codebase:

- [ ] Store the API key/secret in the secrets manager, not in code
- [ ] Add the environment variable name to `.env.example` with a placeholder
- [ ] Add a detection rule to `.gitleaks.toml` for the new secret format
- [ ] Update this document with where the secret lives in production
