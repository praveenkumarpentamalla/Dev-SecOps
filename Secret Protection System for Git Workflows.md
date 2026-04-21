# The Ultimate End-to-End Secret Protection System for Git Workflows

This guide implements a "Shift Left" security strategy combined with a **non-bypassable centralized enforcement** layer. The core philosophy is to educate and assist developers locally but to **never trust** the local environment. The `main` branch is the ultimate source of truth and must be protected at all costs.

Here is the architecture we will build:

1.  **Local Layer (Developer Workstation):** A `pre-commit` hook that runs **Gitleaks** on staged files. It provides instant feedback and prevents a secret from ever being committed to the local repository.
2.  **CI/CD Layer (GitHub Actions):** A mandatory workflow that runs **Gitleaks** on every pull request and push. This is the enforcement point.
3.  **SCM Layer (Branch Protection):** GitHub branch protection rules that make the CI job a required status check. **If the Gitleaks scan fails, the PR cannot be merged. Period.**

---

## Part 1: Local Development Protection (The Educational Net)

This layer is about developer productivity and catching mistakes instantly. We will use the `pre-commit` framework, the industry standard for managing git hooks.

### 1.1 Project Structure Setup

First, let's create the necessary files in your repository's root.

```text
your-repo/
├── .gitleaks.toml        # [File 1] Central config for all Gitleaks scans
├── .pre-commit-config.yaml # [File 2] Manages the local git hook
├── .gitignore            # Ensure local files are not tracked
└── scripts/
    └── install-hooks.sh  # [File 3] Helper script for team onboarding
```

### 1.2 The Configuration Files

**[File 1: `.gitleaks.toml`] - The Detection Rulebook**
This file defines what constitutes a secret. It extends the powerful default rule set and adds custom patterns.

```toml
# .gitleaks.toml
# Production-ready configuration for secret detection

title = "Production Gitleaks Config"

# Extend the excellent default ruleset provided by Gitleaks
# This covers AWS keys, GitHub tokens, JWTs, and hundreds of other patterns.
[extend]
useDefault = true

# Custom rules for organization-specific or uncommon secrets
[[rules]]
id = "custom-anthropic-api-key"
description = "Detects an Anthropic API Key"
regex = '''sk-ant-api03-[a-zA-Z0-9\-_]{40,}'''
tags = ["api_key", "anthropic", "ai"]

[[rules]]
id = "custom-database-connection-string"
description = "Detects common DB connection strings with credentials"
regex = '''(postgresql|mysql|mongodb)://[a-zA-Z0-9]+:[^@\s]+@'''
tags = ["database", "connection_string"]

# The allowlist is for handling false positives.
# NEVER add real, active secrets here. This is for test patterns or known-inert strings.
[allowlist]
description = "Allowlisted files and patterns (test data only)"
paths = ['''test/fixtures/''', '''scripts/secrets-example.py''']
regexes = [
  '''example-secret-do-not-use-[A-Z0-9]+''',
  '''BEGIN PRIVATE KEY-----EXAMPLE-----END PRIVATE KEY'''
]
```

**[File 2: `.pre-commit-config.yaml`] - The Hook Manager**
This config uses the `pre-commit` framework to install and run Gitleaks.

```yaml
# .pre-commit-config.yaml
repos:
  # 1. The core hook to prevent committing to protected branches.
  # This stops a developer from accidentally doing 'git commit -m "fix" --no-verify' on main.
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.5.0
    hooks:
      - id: no-commit-to-branch
        args: [--branch, main, --branch, master]

  # 2. The secret scanner. THIS IS THE MOST IMPORTANT LOCAL HOOK.
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.2  # Use the latest stable version
    hooks:
      - id: gitleaks
        name: SECRETS SCAN (Gitleaks)
        description: Scan for hardcoded secrets before committing.
        entry: gitleaks protect --staged --verbose --redact --config .gitleaks.toml
        language: golang
        pass_filenames: false
        always_run: true
```

**[File 3: `scripts/install-hooks.sh`] - Standardized Team Setup**
This script ensures every developer on the team has the hooks installed identically.

```bash
#!/bin/bash
# scripts/install-hooks.sh
# Usage: ./scripts/install-hooks.sh

set -e
echo "🔒 Setting up secret protection system for your local environment..."

# Check for pre-commit, the dependency manager
if ! command -v pre-commit &> /dev/null
then
    echo "❌ pre-commit could not be found. Installing via pip (or brew)..."
    # It's best to use pip as it's language-agnostic for hooks
    pip install pre-commit
fi

# Install the git hook scripts from our .pre-commit-config.yaml
echo "📦 Installing git hooks from .pre-commit-config.yaml..."
pre-commit install

# (Optional) Install the 'pre-push' hook for an extra layer of safety
# pre-commit install --hook-type pre-push

echo "✅ Success! Git hooks installed. Gitleaks will now scan every commit."
```

**Don't forget to update your `.gitignore`:**

```gitignore
# .gitignore
# Pre-commit's local environment directory
.pre-commit/
```

### 1.3 Onboarding for New Developers
Add this to your `README.md` or `CONTRIBUTING.md`:

```markdown
## Setting up your development environment

1.  Clone the repository.
2.  Run the hook installer script:
    ```bash
    ./scripts/install-hooks.sh
    ```
3.  Done! Now, every commit you make will be automatically scanned for secrets. If a secret is found, the commit will be blocked.

**To bypass in an emergency (not recommended):**
`git commit --no-verify`
**Note:** Bypassing the local hook will not save you. The CI/CD pipeline will still reject your pull request.
```

---

## Part 2: Repository-Level Enforcement (The Unbreakable Wall)

This is where you enforce the rule. We will use a GitHub Action that runs on every push and pull request.

**[File 4: `.github/workflows/gitleaks.yml`] - The CI Enforcer**

```yaml
# .github/workflows/gitleaks.yml
name: Secret Scanner (Gitleaks)

on:
  push:
    branches: [ main, master ]
  pull_request:
    branches: [ main, master ]
  # Allow manual triggering from the Actions tab
  workflow_dispatch:

jobs:
  scan:
    name: Scan for hardcoded secrets
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
        with:
          # 'fetch-depth: 0' is CRITICAL.
          # It tells Git to fetch the entire history so Gitleaks can scan for secrets
          # that might have been introduced in the past. For a PR, it scans the whole branch.
          fetch-depth: 0

      - name: Run Gitleaks
        # Use the official Gitleaks Action. For public repos or personal accounts,
        # no license is needed. For organizations, you need a free license from gitleaks.io.
        uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          # GITLEAKS_LICENSE: ${{ secrets.GITLEAKS_LICENSE }} # <-- Uncomment if you are in a GitHub Organization
        with:
          # Path to our custom config file
          config: .gitleaks.toml
          # Fail the build immediately if any secret is found
          fail_on_finding: true
          # Enable comments on the pull request to show the developer where the leak is
          enable_comments: true
```

**Important Note on Gitleaks License:**
- **Personal Account / Public Repo:** The `gitleaks-action` is free and requires no license key.
- **Organization Account:** You must obtain a **free** license from [gitleaks.io](https://gitleaks.io) and add it as a repository secret named `GITLEAKS_LICENSE`. This is a common point of confusion, so do not skip this.

---

## Part 3: Branch Protection Strategy (The Lock on the Door)

Now, we configure GitHub to **demand** that the secret scan passes before any code can be merged.

### 3.1 Configure Branch Protection Rules

1.  Go to your repository on GitHub.
2.  Navigate to **Settings** -> **Branches** -> **Branch protection rules** -> **Add rule**.
3.  In "Branch name pattern", enter `main` (or `master`).
4.  Check the following boxes:
    - **Require a pull request before merging:** This enforces the PR-only workflow.
    - **Require status checks to pass before merging:** This is the key.
    - **Require branches to be up to date before merging:** Ensures the PR includes the latest changes from `main`.
5.  In the "Status checks that are required" search box, look for and select the job name from our GitHub Action. It will be `Secret Scanner (Gitleaks)` or simply `gitleaks`. **This ties the merge permission directly to the success of the scan.**
6.  **Do not allow bypassing the above settings:** This ensures that even repository admins cannot push directly to `main` or bypass the required checks.
7.  Click **Create**.

Now, if a developer uses `git commit --no-verify` to bypass the local hook, the `git push` will still work, but the pull request they open will fail the required status check, and the "Merge" button will be grayed out.

---

## Part 4: Advanced Security & Alternative Approaches

### 4.1 GitHub Advanced Security (Push Protection)
If your organization has a GitHub Advanced Security license, enable **Push Protection**.
- **How it works:** It scans secrets **server-side** during the `git push` operation itself. If it detects a secret pattern, it will reject the push before the commit is even received by GitHub.
- **Why it's better:** It blocks secrets from ever touching the GitHub server, not just from being merged. It is a superior solution to a CI-based check.
- **Configuration:** This is enabled under your repository's **Settings** -> **Code security and analysis** -> **GitHub Advanced Security** -> **Push protection**.

### 4.2 Server-Side Hooks (For GitLab/Bitbucket)
If you are not on GitHub, the principle is the same:
- **GitLab (Premium/Ultimate):** Use **Push Rules**. You can define a custom regex or enable "Secret detection" which will block the push.
- **Bitbucket (Data Center):** You must implement a **Pre-receive hook**. This is a custom script on the Bitbucket server that runs Gitleaks on every incoming push.

---

## Part 5: Best Practices for a Production System

### 5.1 Handling False Positives
False positives are the #1 reason developers hate security tools. Here's how to manage them gracefully.
1.  **For a single false positive line:** Add a comment `#gitleaks:allow` to the end of the line in your code.
    ```python
    # Example of a false positive test key
    fake_aws_key = "AKIAIOSFODNN7EXAMPLE"  #gitleaks:allow
    ```
2.  **For a pattern or path:** Add the path or regex to the `[allowlist]` section of your `.gitleaks.toml` file.

### 5.2 How to Rotate a Compromised Key
**Crucial:** If a secret is committed, even for a second, **assume it is compromised**.
1.  **Revoke the secret immediately:** Go to AWS IAM, GitHub settings, etc., and delete or rotate the compromised key.
2.  **Remove the secret from Git history:** This is a destructive operation. Use `git filter-repo` or `BFG Repo-Cleaner` to purge the secret from the entire commit history of the branch.
3.  **Rotate again:** Issue a new, uncompromised key and store it in a vault (see below).

### 5.3 Secure Secrets Management (The Real Solution)
**The best way to prevent secret leaks is to never put secrets in code files.**
- **For local development:** Use `.env` files (make sure they are in `.gitignore`!) or `direnv`.
- **For CI/CD:** Use the repository's **Secrets and variables** (`${{ secrets.MY_KEY }}`).
- **For production:** Use a dedicated secrets manager like **HashiCorp Vault**, **AWS Secrets Manager**, or **Azure Key Vault**.

---

## Deliverables: Complete File Summary

Here are all the files you need to copy into your repository.

**1. `.gitleaks.toml`** (Repository Root)
```toml
title = "Production Gitleaks Config"
[extend]
useDefault = true

[[rules]]
id = "custom-anthropic-api-key"
description = "Detects an Anthropic API Key"
regex = '''sk-ant-api03-[a-zA-Z0-9\-_]{40,}'''
tags = ["api_key", "anthropic", "ai"]

[[rules]]
id = "custom-database-connection-string"
description = "Detects common DB connection strings with credentials"
regex = '''(postgresql|mysql|mongodb)://[a-zA-Z0-9]+:[^@\s]+@'''
tags = ["database", "connection_string"]

[allowlist]
description = "Allowlisted files and patterns"
paths = ['''test/fixtures/''', '''scripts/secrets-example.py''']
regexes = [
  '''example-secret-do-not-use-[A-Z0-9]+''',
  '''BEGIN PRIVATE KEY-----EXAMPLE-----END PRIVATE KEY'''
]
```

**2. `.pre-commit-config.yaml`** (Repository Root)
```yaml
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.5.0
    hooks:
      - id: no-commit-to-branch
        args: [--branch, main, --branch, master]
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.2
    hooks:
      - id: gitleaks
        name: SECRETS SCAN (Gitleaks)
        entry: gitleaks protect --staged --verbose --redact --config .gitleaks.toml
        language: golang
        pass_filenames: false
        always_run: true
```

**3. `.github/workflows/gitleaks.yml`** (Repository Root)
```yaml
name: Secret Scanner (Gitleaks)

on:
  push:
    branches: [ main, master ]
  pull_request:
    branches: [ main, master ]
  workflow_dispatch:

jobs:
  scan:
    name: Scan for hardcoded secrets
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - name: Run Gitleaks
        uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          config: .gitleaks.toml
          fail_on_finding: true
          enable_comments: true
```

**4. `scripts/install-hooks.sh`** (Repository Root/scripts)
```bash
#!/bin/bash
set -e
echo "🔒 Setting up secret protection..."
if ! command -v pre-commit &> /dev/null; then
    echo "Installing pre-commit..."
    pip install pre-commit
fi
pre-commit install
echo "✅ Success! Hooks are installed."
```

By implementing this complete system, you have created a defense-in-depth strategy that is resilient to individual developer mistakes or bypass attempts. The local hook provides speed and convenience, while the required CI check on protected branches provides absolute, centralized enforcement.
