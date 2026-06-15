#!/bin/bash
# Install the scaffold into a target repository.
#
# Creates symlinks from the target repo to this scaffold repo, and (when
# running outside a container) wires up the devcontainer that will host
# Claude Code so the symlinks resolve at runtime.
#
# Usage: ./install.sh /path/to/target_repo
set -euo pipefail

SCAFFOLD_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="${1:?Usage: ./install.sh /path/to/target_repo}"

# Derive scaffold-specific names from the scaffold directory so the install
# script stays neutral if the repo is renamed or forked. The in-container
# mount path lives under /opt/ (FHS-standard location for optional add-on
# software) and uses the scaffold's directory name, so it never accidentally
# implies it belongs to a particular target eval repo.
SCAFFOLD_NAME="$(basename "$SCAFFOLD_DIR")"
CONTAINER_SCAFFOLD="/opt/$SCAFFOLD_NAME"

# Override env var, also derived from the scaffold name so it can't collide
# with another scaffold's override. E.g. for a scaffold dir named "prism",
# this resolves to PRISM_INSTALL_MODE; for "my-scaffold" -> MY_SCAFFOLD_INSTALL_MODE.
MODE_OVERRIDE_VAR="$(echo "$SCAFFOLD_NAME" | tr '[:lower:]-' '[:upper:]_')_INSTALL_MODE"

if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: $TARGET_DIR is not a directory"
    exit 1
fi

TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

# --- Mode detection: in_container vs host ---
# Two install modes:
#
#   in_container  Install is running inside the same container Claude Code
#                 will run in, so $SCAFFOLD_DIR is a stable path that the
#                 symlinks can point at directly. No devcontainer changes
#                 needed.
#
#   host          Install is running on the host. $SCAFFOLD_DIR is a host-
#                 only path that won't exist inside a future container, so
#                 symlinks instead point at $CONTAINER_SCAFFOLD and the
#                 target's devcontainer is patched (or scaffolded from a
#                 template if missing) to bind-mount the scaffold there.
#
# Auto-detection uses well-known signals: /.dockerenv (Docker, incl. VS Code
# devcontainers and Codespaces) and /run/.containerenv (Podman). Falls back
# to env vars Codespaces/Dev Containers set. For other container runtimes
# that don't drop these markers, set $MODE_OVERRIDE_VAR=in_container|host
# explicitly.
detect_inside_container() {
    [ -f /.dockerenv ] && return 0
    [ -f /run/.containerenv ] && return 0
    [ -n "${REMOTE_CONTAINERS:-}" ] && return 0
    [ -n "${CODESPACES:-}" ] && return 0
    return 1
}

MODE="${!MODE_OVERRIDE_VAR:-auto}"
if [ "$MODE" = "auto" ]; then
    if detect_inside_container; then
        MODE="in_container"
    else
        MODE="host"
    fi
fi

case "$MODE" in
    in_container) SCAFFOLD_SRC="$SCAFFOLD_DIR" ;;
    host)         SCAFFOLD_SRC="$CONTAINER_SCAFFOLD" ;;
    *)
        echo "Error: $MODE_OVERRIDE_VAR must be one of: auto, in_container, host (got: $MODE)"
        exit 1
        ;;
esac

echo "Installing $SCAFFOLD_NAME scaffold"
echo "  Scaffold:     $SCAFFOLD_DIR"
echo "  Target:       $TARGET_DIR"
echo "  Mode:         $MODE"
echo "  Symlinks to:  $SCAFFOLD_SRC"
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

# --- Helper: create a symlink pointing at the mode-appropriate scaffold src ---
link_file() {
    local rel_path="$1"
    local src="$SCAFFOLD_SRC/$rel_path"
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

# .claude/docs
link_file ".claude/docs/analyst_delegation_guide.md"
link_file ".claude/docs/analyst_interface_contract.md"
link_file ".claude/docs/eval_science_principles.md"
link_file ".claude/docs/executor_interface_contract.md"
link_file ".claude/docs/explorer_interface_contract.md"
link_file ".claude/docs/inspect_reference.md"
link_file ".claude/docs/orchestrator_responsibilities.md"
link_file ".claude/docs/scout_reference.md"
link_file ".claude/docs/subagent_invocation.md"

# .claude/skills/orchestrator
link_file ".claude/skills/orchestrator/SKILL.md"
link_file ".claude/skills/orchestrator/experimental-design-patterns.md"
link_file ".claude/skills/orchestrator/hypothesis-methodology.md"

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
    "# $SCAFFOLD_NAME scaffold (symlinks managed by $SCAFFOLD_NAME/install.sh)"
    "subagents/"
    "scripts/execute_evals.py"
    ".claude/docs/analyst_delegation_guide.md"
    ".claude/docs/analyst_interface_contract.md"
    ".claude/docs/eval_science_principles.md"
    ".claude/docs/executor_interface_contract.md"
    ".claude/docs/explorer_interface_contract.md"
    ".claude/docs/inspect_reference.md"
    ".claude/docs/orchestrator_responsibilities.md"
    ".claude/docs/scout_reference.md"
    ".claude/docs/subagent_invocation.md"
    ".claude/skills/orchestrator/"
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

# --- Devcontainer wiring (host mode only) ---
# Only relevant when we're installing on the host and the symlinks point at
# $CONTAINER_SCAFFOLD: we need a devcontainer that will mount the scaffold
# there. In in_container mode the symlinks already point at $SCAFFOLD_DIR
# directly, so no devcontainer changes are needed.
DEVCONTAINER="$TARGET_DIR/.devcontainer/devcontainer.json"
DEVCONTAINER_PATCHED=0
if [ "$MODE" = "host" ]; then
    # If the target has no devcontainer, drop in the scaffold's template so
    # the same patching code can then wire in the mount. Keeps the after-
    # install state uniform regardless of what the target shipped with.
    if [ ! -f "$DEVCONTAINER" ]; then
        TEMPLATE="$SCAFFOLD_DIR/templates/devcontainer.json"
        if [ -f "$TEMPLATE" ]; then
            mkdir -p "$TARGET_DIR/.devcontainer"
            cp "$TEMPLATE" "$DEVCONTAINER"
            echo ""
            echo "Scaffolded devcontainer.json from $SCAFFOLD_NAME template"
        else
            echo ""
            echo "  WARNING: target has no .devcontainer/devcontainer.json and the"
            echo "  $SCAFFOLD_NAME template at $TEMPLATE doesn't exist yet."
            echo "  Devcontainer setup skipped. You can either:"
            echo "    - add a devcontainer.json to the target manually, then re-run install,"
            echo "    - or set $MODE_OVERRIDE_VAR=in_container if you're running inside the"
            echo "      same container Claude Code will use (symlinks will then point at"
            echo "      $SCAFFOLD_DIR directly)."
        fi
    fi

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

        # Delegate the actual JSON edit to a Python script in scripts/.
        # The script handles JSONC input (// and /* */ comments are stripped
        # before parsing) so real-world devcontainer.json files don't trip
        # the patcher, and is idempotent — re-running install is safe.
        python3 "$SCAFFOLD_DIR/scripts/_patch_devcontainer.py" \
            "$DEVCONTAINER" "$MOUNT_SOURCE" "$CONTAINER_SCAFFOLD"
    fi
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
if [ "$MODE" = "in_container" ]; then
    echo "  $step. Launch Claude Code from inside the target repo (cd \"$TARGET_DIR\"),"
    echo "      since skill discovery is rooted at the current working directory"
    step=$((step + 1))
elif [ "$DEVCONTAINER_PATCHED" = "1" ]; then
    echo "  $step. Reopen the target repo in its devcontainer so the scaffold mount"
    echo "      takes effect (e.g. VS Code's \"Reopen in Container\", or your tool's equivalent)"
    step=$((step + 1))
else
    echo "  $step. Make the scaffold available at $CONTAINER_SCAFFOLD wherever Claude Code"
    echo "      runs (the installed symlinks resolve to that path), or re-run install once"
    echo "      a devcontainer is in place"
    step=$((step + 1))
fi
echo "  $step. Add your API keys to a .env file in the target repo: ANTHROPIC_API_KEY"
echo "      is required; OPENAI_API_KEY only if your eval or grader uses OpenAI"
step=$((step + 1))
echo "  $step. (Optional) create .claude/settings.local.json for local overrides"
step=$((step + 1))
echo "  $step. Launch the orchestrator in Claude Code: /orchestrator [research question]"
echo ""
echo "Tip: run the Orchestrator on the most recent Claude model available —"
echo "we observed weaker scaffold compliance on older models (e.g. Opus 4.5)."
