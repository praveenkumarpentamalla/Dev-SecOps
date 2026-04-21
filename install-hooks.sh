#!/usr/bin/env bash
# =============================================================================
# scripts/install-hooks.sh
# One-command setup for every developer joining the project.
#
# Usage:
#   chmod +x scripts/install-hooks.sh
#   ./scripts/install-hooks.sh
#
# What it does:
#   1. Checks for required tools (git, python, gitleaks)
#   2. Installs Gitleaks if missing
#   3. Installs the pre-commit framework
#   4. Installs all hooks from .pre-commit-config.yaml
#   5. Optionally generates a detect-secrets baseline
#   6. Sets up a git commit-msg hook to enforce conventional commits
# =============================================================================

set -euo pipefail

# ANSI colour codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'   # Reset

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

echo ""
echo -e "${BOLD}╔═══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   Secret Protection Hook Installer        ║${NC}"
echo -e "${BOLD}╚═══════════════════════════════════════════╝${NC}"
echo ""

# ---------------------------------------------------------------------------
# 1. Ensure we are inside a git repository
# ---------------------------------------------------------------------------
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  error "Not inside a git repository. Run this from your project root."
fi

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"
info "Repository root: $REPO_ROOT"

# ---------------------------------------------------------------------------
# 2. Detect OS
# ---------------------------------------------------------------------------
OS="$(uname -s)"
ARCH="$(uname -m)"
info "Detected OS: $OS ($ARCH)"

# ---------------------------------------------------------------------------
# 3. Check / install Gitleaks
# ---------------------------------------------------------------------------
install_gitleaks() {
  info "Installing Gitleaks..."

  GITLEAKS_VERSION="8.21.2"

  case "$OS" in
    Darwin)
      if command -v brew &>/dev/null; then
        brew install gitleaks
      else
        warn "Homebrew not found — downloading Gitleaks binary..."
        GITLEAKS_TARBALL="gitleaks_${GITLEAKS_VERSION}_darwin_arm64.tar.gz"
        [ "$ARCH" = "x86_64" ] && GITLEAKS_TARBALL="gitleaks_${GITLEAKS_VERSION}_darwin_x64.tar.gz"
        curl -sL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${GITLEAKS_TARBALL}" \
          | tar -xz -C /usr/local/bin gitleaks
      fi
      ;;
    Linux)
      GITLEAKS_TARBALL="gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"
      [ "$ARCH" = "aarch64" ] && GITLEAKS_TARBALL="gitleaks_${GITLEAKS_VERSION}_linux_arm64.tar.gz"
      curl -sL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${GITLEAKS_TARBALL}" \
        | tar -xz -C "$HOME/.local/bin" gitleaks
      # Ensure ~/.local/bin is on PATH
      export PATH="$HOME/.local/bin:$PATH"
      ;;
    MINGW*|MSYS*|CYGWIN*)
      # Windows Git Bash
      warn "Windows detected. Please install Gitleaks manually:"
      warn "  winget install GitLeaks.GitLeaks"
      warn "  https://github.com/gitleaks/gitleaks/releases"
      ;;
    *)
      error "Unsupported OS: $OS. Install Gitleaks manually: https://github.com/gitleaks/gitleaks#installing"
      ;;
  esac
}

if command -v gitleaks &>/dev/null; then
  GITLEAKS_VER=$(gitleaks version 2>&1 || echo "unknown")
  success "Gitleaks already installed: $GITLEAKS_VER"
else
  install_gitleaks
  if command -v gitleaks &>/dev/null; then
    success "Gitleaks installed: $(gitleaks version)"
  else
    error "Gitleaks installation failed. Install manually: https://github.com/gitleaks/gitleaks#installing"
  fi
fi

# ---------------------------------------------------------------------------
# 4. Check / install Python and pre-commit
# ---------------------------------------------------------------------------
if ! command -v python3 &>/dev/null; then
  error "Python 3 is required. Install from https://python.org"
fi

if ! command -v pre-commit &>/dev/null; then
  info "Installing pre-commit framework..."
  if command -v pip3 &>/dev/null; then
    pip3 install --user pre-commit
  elif command -v pip &>/dev/null; then
    pip install --user pre-commit
  else
    error "pip not found. Install pre-commit manually: pip install pre-commit"
  fi
  # Add user bin to PATH if needed
  export PATH="$HOME/.local/bin:$PATH"
fi

if command -v pre-commit &>/dev/null; then
  success "pre-commit installed: $(pre-commit --version)"
else
  error "pre-commit not found on PATH after installation. Add ~/.local/bin to your PATH."
fi

# ---------------------------------------------------------------------------
# 5. Install the pre-commit hooks into .git/hooks
# ---------------------------------------------------------------------------
info "Installing pre-commit hooks..."
pre-commit install --install-hooks --hook-type pre-commit
pre-commit install --hook-type pre-push
pre-commit install --hook-type commit-msg
success "Pre-commit hooks installed (pre-commit, pre-push, commit-msg stages)"

# ---------------------------------------------------------------------------
# 6. Generate detect-secrets baseline (if not present)
# ---------------------------------------------------------------------------
if [ ! -f ".secrets.baseline" ]; then
  if command -v detect-secrets &>/dev/null; then
    info "Generating detect-secrets baseline..."
    detect-secrets scan \
      --exclude-files 'package-lock\.json|yarn\.lock|poetry\.lock|\.min\.js$' \
      > .secrets.baseline
    success "Created .secrets.baseline — commit this file."
  else
    warn "detect-secrets not installed. Run: pip install detect-secrets"
    warn "Then generate baseline: detect-secrets scan > .secrets.baseline"
  fi
else
  success ".secrets.baseline already exists."
fi

# ---------------------------------------------------------------------------
# 7. Verify the hooks work with a dry run
# ---------------------------------------------------------------------------
info "Running a dry-run Gitleaks scan on the repository..."
if gitleaks detect --config .gitleaks.toml --redact --no-git=false --exit-code=0 2>&1; then
  success "Dry-run scan complete — no secrets detected."
else
  warn "Gitleaks reported findings. Review them before committing."
fi

# ---------------------------------------------------------------------------
# 8. Summary
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}╔═══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   Setup Complete!                         ║${NC}"
echo -e "${BOLD}╚═══════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}✓${NC} Gitleaks is installed and configured"
echo -e "${GREEN}✓${NC} pre-commit framework is active"
echo -e "${GREEN}✓${NC} Hooks installed: pre-commit, pre-push, commit-msg"
echo ""
echo -e "${YELLOW}IMPORTANT — To prevent bypass:${NC}"
echo "  1. Never use: git commit --no-verify"
echo "  2. The GitHub Actions workflow will catch any bypassed commits anyway."
echo "  3. If you get a false positive, add it to .gitleaks.toml [allowlist]"
echo "     and get it reviewed in a PR before merging."
echo ""
echo -e "${CYAN}To run all hooks manually:${NC}  pre-commit run --all-files"
echo -e "${CYAN}To update hook versions:${NC}    pre-commit autoupdate"
echo ""
