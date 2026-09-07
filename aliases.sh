# OpenShell sandbox helpers. Source from ~/.bashrc or ~/.bash_aliases:
#
#     . /path/to/openshell-agent/aliases.sh
#
# `os` gets you into a sandbox named after the first argument (default: dev),
# creating it only if it isn't there yet. With no `--` you land in a shell, as
# with a bare `openshell sandbox create`; anything after `--` is the main process
# to run instead:
#
#   os                # shell in `dev`, creating it on first use
#   os scratch        # a second, separate sandbox
#   os dev -- claude  # start Claude Code as the main process
#
# NOTE: exiting the sandbox's main process stops the container, and OpenShell
# then reports the sandbox as `Error` rather than `Stopped` -- that is what the
# Error phase means, not a crash. To leave a sandbox running, detach with
# Ctrl-P Ctrl-Q instead of exiting.

# Where this repo lives; override to point at a checkout elsewhere.
OPENSHELL_AGENT_DIR="${OPENSHELL_AGENT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

openshell-session() {
    local name=dev
    if [ $# -gt 0 ] && [ "$1" != "--" ]; then name=$1; shift; fi
    [ "$1" = "--" ] && shift
    local phase
    phase=$(openshell sandbox get "$name" -o json 2>/dev/null \
            | python3 -c 'import sys,json;print(json.load(sys.stdin)["phase"])' 2>/dev/null)

    case "$phase" in
        Ready)
            openshell sandbox connect "$name"
            ;;
        "")
            # No args -> no `--`, so openshell picks its own default shell.
            openshell sandbox create \
                --name   "$name" \
                --from   "$OPENSHELL_AGENT_DIR/sandbox-current-claude" \
                --policy "$OPENSHELL_AGENT_DIR/sandbox-policy.yaml" \
                ${1+--} "$@"
            ;;
        *)
            # Stopped, Error, or anything else with a workspace still on disk.
            echo "sandbox '$name' is $phase; starting it" >&2
            openshell sandbox start "$name" && openshell sandbox connect "$name"
            ;;
    esac
}
alias os='openshell-session'
alias osl='openshell sandbox list'
