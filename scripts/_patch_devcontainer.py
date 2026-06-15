"""Patch a target repo's devcontainer.json to wire in the Prism scaffold.

Used by install.sh during a host-mode install. Idempotently adds the bind
mount for the scaffold and the Claude Code devcontainer feature. Tolerates
JSONC (// line comments and /* */ block comments) on input, since many
real-world devcontainer.json files are JSONC even though the schema is
spec'd as JSON. Writes back as strict JSON.

This script lives in `scripts/` alongside `execute_evals.py` but, unlike
that script, is *not* symlinked into the target repo — it's an install-time
tool only, invoked from install.sh as
`python3 $SCAFFOLD_DIR/scripts/_patch_devcontainer.py …`.

Usage
-----
    _patch_devcontainer.py <devcontainer.json> <mount_source> <mount_target>
"""

import json
import sys


CLAUDE_FEATURE = "ghcr.io/anthropics/devcontainer-features/claude-code:latest"


def strip_jsonc(text):
    """Strip JSONC comments while leaving comment-like sequences in strings alone.

    Hand-rolled rather than pulling in a dep (json5, commentjson, etc.):
    install.sh shouldn't require anything beyond the stdlib. Single-pass
    state machine over the characters, tracking whether we're inside a
    double-quoted string and whether the previous character was an escape.
    Newlines inside block comments are preserved so that line numbers in
    any subsequent parse error stay approximately correct.

    Parameters
    ----------
    text : str
        Raw devcontainer.json contents, possibly containing // or /* */
        comments.

    Returns
    -------
    str
        Strict-JSON-parseable text with comments removed.
    """
    out = []
    i = 0
    n = len(text)
    in_string = False
    while i < n:
        c = text[i]
        if in_string:
            # Inside a string: copy verbatim. Honour backslash escapes so an
            # escaped quote doesn't prematurely close the string.
            if c == "\\" and i + 1 < n:
                out.append(text[i:i + 2])
                i += 2
                continue
            out.append(c)
            if c == '"':
                in_string = False
            i += 1
            continue

        if c == '"':
            in_string = True
            out.append(c)
            i += 1
        elif c == "/" and i + 1 < n and text[i + 1] == "/":
            # Line comment: skip to end of line; let the newline fall through
            # so line counts in downstream errors are preserved.
            while i < n and text[i] != "\n":
                i += 1
        elif c == "/" and i + 1 < n and text[i + 1] == "*":
            # Block comment: skip to closing */. Preserve any newlines inside
            # so error line numbers stay roughly accurate.
            i += 2
            while i + 1 < n and not (text[i] == "*" and text[i + 1] == "/"):
                if text[i] == "\n":
                    out.append("\n")
                i += 1
            i += 2  # consume the closing */
        else:
            out.append(c)
            i += 1
    return "".join(out)


def main():
    devcontainer_path, mount_source, mount_target = sys.argv[1:4]

    # --- Read and parse ---
    with open(devcontainer_path) as f:
        raw = f.read()
    stripped = strip_jsonc(raw)
    had_comments = stripped != raw
    config = json.loads(stripped)

    # --- Scaffold bind mount ---
    # Match by `target` (not source) so a re-install with the same mount
    # target but different source still counts as already-present. install.sh
    # always uses the in-container scaffold path as the target.
    mounts = config.setdefault("mounts", [])
    mount_present = any(
        isinstance(m, dict) and m.get("target") == mount_target
        for m in mounts
    )
    if mount_present:
        print("  Already present: scaffold mount in devcontainer.json")
    else:
        mounts.append({
            "source": mount_source,
            "target": mount_target,
            "type": "bind",
        })
        print("  Added scaffold mount to devcontainer.json")

    # --- Claude Code devcontainer feature ---
    features = config.setdefault("features", {})
    if CLAUDE_FEATURE in features:
        print("  Already present: Claude Code feature in devcontainer.json")
    else:
        features[CLAUDE_FEATURE] = {}
        print("  Added Claude Code feature to devcontainer.json")

    # --- Write back as strict JSON ---
    with open(devcontainer_path, "w") as f:
        json.dump(config, f, indent=2)
        f.write("\n")

    if had_comments:
        # The patched file is strict JSON; the user's comments don't survive
        # the round-trip. Their original is preserved by install.sh as
        # devcontainer.json.pre-scaffold, so recovery is one mv away.
        print("  Note: JSONC comments dropped during patching")
        print("        (original retained as devcontainer.json.pre-scaffold)")


if __name__ == "__main__":
    main()
