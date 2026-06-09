#!/bin/bash
# Install the eval-science scaffold into a target repository.
#
# Creates symlinks from the target repo to this scaffold repo,
# patches devcontainer.json to mount the scaffold into the container,
# and sets up .gitignore.
#
# Usage: ./install.sh /path/to/inspect_ai
set -euo pipefail

SCAFFOLD_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="${1:?Usage: ./install.sh /path/to/target_repo}"

# In-container path where the scaffold will be mounted.
CONTAINER_SCAFFOLD="/home/inspect/prism"

if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: $TARGET_DIR is not a directory"
    exit 1
fi

TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

echo "Installing eval-science scaffold"
echo "  Scaffold: $SCAFFOLD_DIR"
echo "  Target:   $TARGET_DIR"
echo "  Container mount: $CONTAINER_SCAFFOLD"
echo ""

# In-target marker tracking symlinked directories that install.sh promoted
# to real directories. Used by uninstall.sh to reverse them. Each line:
# "<absolute-target-path>\t<absolute-upstream-path>"
LOCALIZATION_MARKER="$TARGET_DIR/.scaffold-localizations"

# --- Helper: promote a symlinked directory to a real directory ---
# Replaces a symlink-to-directory with a real directory whose entries are
# individual symlinks back to each item in the original upstream. Existing
# content stays readable and edits to existing files still propagate, while
# new entries under this path land locally in the target rather than
# leaking into the upstream.
promote_symlink() {
    local path="$1"

    [ -L "$path" ] || return 0
    [ -d "$path" ] || return 0

    local upstream
    upstream="$(readlink -f "$path")"

    rm "$path"
    mkdir "$path"

    shopt -s dotglob nullglob
    local entry name
    for entry in "$upstream"/*; do
        name="$(basename "$entry")"
        ln -s "$entry" "$path/$name"
    done
    shopt -u dotglob nullglob

    printf '%s\t%s\n' "$path" "$upstream" >> "$LOCALIZATION_MARKER"
    echo "  Localized: ${path#$TARGET_DIR/} (was symlink -> $upstream)"
}

# --- Helper: ensure a directory path is local to the target ---
# Walks from $TARGET_DIR down to $1 (recursively), promoting any symlinked
# directory it finds and creating missing directories as needed. After this
# returns, every ancestor of $1 (and $1 itself) is a real directory inside
# $TARGET_DIR — so leaf writes below $1 land locally, without leaking to
# any symlink target. Idempotent: no-op if everything is already real.
ensure_local_dir() {
    local path="$1"

    [ "$path" = "$TARGET_DIR" ] && return 0
    ensure_local_dir "$(dirname "$path")"

    if [ -L "$path" ] && [ -d "$path" ]; then
        promote_symlink "$path"
    elif [ ! -e "$path" ]; then
        mkdir "$path"
    fi
}

# --- Helper: create a symlink pointing to the in-container path ---
link_file() {
    local rel_path="$1"
    local src="$CONTAINER_SCAFFOLD/$rel_path"
    local dst="$TARGET_DIR/$rel_path"
    local dst_dir
    dst_dir="$(dirname "$dst")"

    ensure_local_dir "$dst_dir"

    if [ -L "$dst" ]; then
        rm "$dst"
    elif [ -e "$dst" ]; then
        echo "  SKIP (exists): $rel_path"
        return
    fi

    ln -s "$src" "$dst"
    echo "  Linked: $rel_path"
}

# --- Symlink all scaffold files ---
echo "Creating symlinks..."

# scripts
link_file "scripts/execute_evals.py"

# subagents
link_file "subagents/__init__.py"
link_file "subagents/cli.py"
link_file "subagents/runner.py"

link_file "subagents/environment_explorer/__init__.py"
link_file "subagents/environment_explorer/agent.py"
link_file "subagents/environment_explorer/main.py"
link_file "subagents/environment_explorer/system_prompt.py"

link_file "subagents/experiment_executor/__init__.py"
link_file "subagents/experiment_executor/agent.py"
link_file "subagents/experiment_executor/main.py"
link_file "subagents/experiment_executor/system_prompt.py"

link_file "subagents/transcript_analyst/__init__.py"
link_file "subagents/transcript_analyst/agent.py"
link_file "subagents/transcript_analyst/main.py"
link_file "subagents/transcript_analyst/system_prompt.py"

link_file "subagents/eval_reader/__init__.py"
link_file "subagents/eval_reader/agent.py"
link_file "subagents/eval_reader/main.py"
link_file "subagents/eval_reader/system_prompt.py"

link_file "subagents/cot_analyst/__init__.py"
link_file "subagents/cot_analyst/agent.py"
link_file "subagents/cot_analyst/main.py"
link_file "subagents/cot_analyst/system_prompt.py"

link_file "subagents/experiment_designer/__init__.py"
link_file "subagents/experiment_designer/agent.py"
link_file "subagents/experiment_designer/main.py"
link_file "subagents/experiment_designer/system_prompt.py"

link_file "subagents/reviewer/__init__.py"
link_file "subagents/reviewer/agent.py"
link_file "subagents/reviewer/main.py"
link_file "subagents/reviewer/system_prompt.py"

# .claude/docs
link_file ".claude/docs/analyst_delegation_guide.md"
link_file ".claude/docs/analyst_interface_contract.md"
link_file ".claude/docs/cot_analyst_interface_contract.md"
link_file ".claude/docs/eval_reader_interface_contract.md"
link_file ".claude/docs/eval_science_principles.md"
link_file ".claude/docs/executor_interface_contract.md"
link_file ".claude/docs/experiment_designer_interface_contract.md"
link_file ".claude/docs/explorer_interface_contract.md"
link_file ".claude/docs/inspect_reference.md"
link_file ".claude/docs/orchestrator_responsibilities.md"
link_file ".claude/docs/reviewer_interface_contract.md"
link_file ".claude/docs/scout_reference.md"
link_file ".claude/docs/subagent_invocation.md"

# .claude/skills/orchestrator
link_file ".claude/skills/orchestrator/SKILL.md"
link_file ".claude/skills/orchestrator/experimental-design-patterns.md"
link_file ".claude/skills/orchestrator/hypothesis-methodology.md"

# .claude/skills/investigate
link_file ".claude/skills/investigate/SKILL.md"

# .claude/settings.json
link_file ".claude/settings.json"

# --- Handle .gitignore (backup and append scaffold entries) ---
echo ""
echo "Updating .gitignore..."
if [ -f "$TARGET_DIR/.gitignore" ] && [ ! -f "$TARGET_DIR/.gitignore.pre-scaffold" ]; then
    cp "$TARGET_DIR/.gitignore" "$TARGET_DIR/.gitignore.pre-scaffold"
    echo "  Backed up .gitignore to .gitignore.pre-scaffold"
fi
GITIGNORE_ENTRIES=(
    ""
    "# Eval Science Scaffold (symlinks managed by prism/install.sh)"
    "subagents/"
    "scripts/execute_evals.py"
    ".claude/docs/analyst_delegation_guide.md"
    ".claude/docs/analyst_interface_contract.md"
    ".claude/docs/cot_analyst_interface_contract.md"
    ".claude/docs/eval_reader_interface_contract.md"
    ".claude/docs/eval_science_principles.md"
    ".claude/docs/executor_interface_contract.md"
    ".claude/docs/experiment_designer_interface_contract.md"
    ".claude/docs/explorer_interface_contract.md"
    ".claude/docs/inspect_reference.md"
    ".claude/docs/orchestrator_responsibilities.md"
    ".claude/docs/reviewer_interface_contract.md"
    ".claude/docs/scout_reference.md"
    ".claude/docs/subagent_invocation.md"
    ".claude/skills/orchestrator/"
    ".claude/skills/investigate/"
    ".claude/settings.json"
    ".claude/autopilot/"
    "CLAUDE.local.md"
    ".devcontainer/devcontainer.json.pre-scaffold"
    ".gitignore.pre-scaffold"
    ".scaffold-localizations"
)
for entry in "${GITIGNORE_ENTRIES[@]}"; do
    if [ -f "$TARGET_DIR/.gitignore" ] && grep -qF "$entry" "$TARGET_DIR/.gitignore"; then
        echo "  Already present: $entry"
    else
        echo "$entry" >> "$TARGET_DIR/.gitignore"
        echo "  Appended: $entry"
    fi
done

# --- Configure git hooks for the scaffold repo ---
echo ""
echo "Configuring git hooks..."
if [ -d "$SCAFFOLD_DIR/.git" ]; then
    git -C "$SCAFFOLD_DIR" config core.hooksPath .githooks
    echo "  Activated .githooks/pre-commit for scaffold repo"
else
    echo "  SKIP: scaffold directory is not a git repo"
fi

# --- Patch devcontainer.json to mount the scaffold repo ---
DEVCONTAINER="$TARGET_DIR/.devcontainer/devcontainer.json"
DEVCONTAINER_PATCHED=0
if [ -f "$DEVCONTAINER" ]; then
    DEVCONTAINER_PATCHED=1
    echo ""
    echo "Patching devcontainer.json..."

    # Backup original devcontainer.json before patching.
    if [ ! -f "$DEVCONTAINER.pre-scaffold" ]; then
        cp "$DEVCONTAINER" "$DEVCONTAINER.pre-scaffold"
        echo "  Backed up devcontainer.json to devcontainer.json.pre-scaffold"
    fi

    # Compute relative path from target repo to scaffold repo.
    # Use python3 for portability (macOS realpath lacks --relative-to).
    REL_PATH="$(python3 -c "import os, sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))" "$SCAFFOLD_DIR" "$TARGET_DIR")"
    MOUNT_SOURCE="\${localWorkspaceFolder}/$REL_PATH"

    # Use python3 to safely add the mount entry if not already present.
    python3 -c "
import json, sys

devcontainer_path = sys.argv[1]
mount_source = sys.argv[2]
mount_target = sys.argv[3]

with open(devcontainer_path) as f:
    config = json.load(f)

mounts = config.setdefault('mounts', [])

# Check if mount already exists.
mount_present = any(
    isinstance(m, dict) and m.get('target') == mount_target
    for m in mounts
)

if mount_present:
    print('  Already present: scaffold mount in devcontainer.json')
else:
    mounts.append({
        'source': mount_source,
        'target': mount_target,
        'type': 'bind'
    })
    print('  Added scaffold mount to devcontainer.json')

# --- Add Claude Code devcontainer feature ---
CLAUDE_FEATURE = 'ghcr.io/anthropics/devcontainer-features/claude-code:latest'
features = config.setdefault('features', {})
 
if CLAUDE_FEATURE in features:
    print('  Already present: Claude Code feature in devcontainer.json')
else:
    features[CLAUDE_FEATURE] = {}
    print('  Added Claude Code feature to devcontainer.json')

with open(devcontainer_path, 'w') as f:
    json.dump(config, f, indent=2)
    f.write('\n')

" "$DEVCONTAINER" "$MOUNT_SOURCE" "$CONTAINER_SCAFFOLD"
else
    echo ""
    echo "  No .devcontainer/devcontainer.json found — skipping container setup."
    echo "  If using a devcontainer, manually mount $SCAFFOLD_DIR at $CONTAINER_SCAFFOLD"
fi

# --- Tell git to ignore local changes to patched upstream files ---
echo ""
echo "Marking patched files as assume-unchanged in git..."
if [ -d "$TARGET_DIR/.git" ]; then
    git -C "$TARGET_DIR" update-index --assume-unchanged \
        .devcontainer/devcontainer.json \
        .gitignore \
        2>/dev/null || true
    echo "  Done (git status will stay clean)"
else
    echo "  SKIP: target is not a git repo"
fi

echo ""
echo "Installation complete."
echo ""
echo "Next steps:"
step=1
echo "  $step. Ensure Claude Code is installed (https://claude.com/product/claude-code)"
step=$((step + 1))
if [ "$DEVCONTAINER_PATCHED" = "1" ]; then
    echo "  $step. Reopen the target repo in its devcontainer so the scaffold mount"
    echo "      takes effect (e.g. VS Code's \"Reopen in Container\", or your tool's equivalent)"
    step=$((step + 1))
else
    echo "  $step. Make the scaffold available at $CONTAINER_SCAFFOLD wherever Claude Code"
    echo "      runs (the installed symlinks resolve to that path)"
    step=$((step + 1))
fi
echo "  $step. Add your API keys to a .env file in the target repo: ANTHROPIC_API_KEY"
echo "      is required; OPENAI_API_KEY only if your eval or grader uses OpenAI"
step=$((step + 1))
echo "  $step. (Optional) create .claude/settings.local.json for local overrides"
step=$((step + 1))
echo "  $step. Launch an investigation in Claude Code:"
echo "      /orchestrator [research question]  — hypothesis-first investigation"
echo "      /investigate <eval_path> <transcripts_path>  — behavior-first model incrimination"
echo ""
echo "Tip: run the Orchestrator on the most recent Claude model available —"
echo "we observed weaker scaffold compliance on older models (e.g. Opus 4.5)."
