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
# NOTE: on the first `os <name>` you are attached to the sandbox's main process,
# and exiting that process stops the container -- OpenShell then reports the
# sandbox as `Error` rather than `Stopped`, which is what the Error phase means
# here, not a crash. Detach with Ctrl-P Ctrl-Q to leave it running. Later
# `os <name>` calls run a separate shell via `exec`, so exiting those is safe.
#
# `Error` is UNRECOVERABLE: both `start` and `stop` refuse it, so the workspace
# (including the Claude Code login) is gone and the only way out is `delete` +
# a fresh `create`. `os` will not do that for you -- it prints the command.

# Where this repo lives; override to point at a checkout elsewhere.
OPENSHELL_AGENT_DIR="${OPENSHELL_AGENT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# Which sandboxes/<name> to build from. One directory per sandbox, upstream's layout.
OPENSHELL_SANDBOX="${OPENSHELL_SANDBOX:-compute}"

# Attach to a running sandbox. Deliberately NOT `openshell sandbox connect`:
# connect reattaches to the sandbox's canonical main process, and if that
# process was launched without a pty (`tty_nr=0`, which is what you get unless
# `create` saw a terminal on both stdin and stdout) it never becomes an
# interactive shell -- no prompt, no echo, no line editing. It still runs what
# you type, so it looks like connect is hanging. `exec --tty` allocates a fresh
# pty instead, so we always get a real shell.
openshell-attach() {
    local name=$1; shift
    if [ $# -gt 0 ]; then
        openshell sandbox exec -n "$name" --tty -- "$@"
    else
        openshell sandbox exec -n "$name" --tty -- bash -l
    fi
}

openshell-session() {
    local name=dev
    if [ $# -gt 0 ] && [ "$1" != "--" ]; then name=$1; shift; fi
    [ "$1" = "--" ] && shift
    local phase
    phase=$(openshell sandbox get "$name" -o json 2>/dev/null \
            | python3 -c 'import sys,json;print(json.load(sys.stdin)["phase"])' 2>/dev/null)

    case "$phase" in
        Ready)
            openshell-attach "$name" "$@"
            ;;
        "")
            # No args -> no `--`, so openshell picks its own default shell.
            openshell sandbox create \
                --name   "$name" \
                --from   "$OPENSHELL_AGENT_DIR/sandboxes/$OPENSHELL_SANDBOX" \
                --policy "$OPENSHELL_AGENT_DIR/sandboxes/$OPENSHELL_SANDBOX/policy.yaml" \
                --tty \
                ${1+--} "$@"
            ;;
        Stopped)
            # Workspace still on disk; start puts it back exactly as it was.
            echo "sandbox '$name' is Stopped; starting it" >&2
            openshell sandbox start "$name" && openshell-attach "$name" "$@"
            ;;
        Error)
            # Terminal: `start` refuses ("must be Stopped"), `stop` refuses
            # ("must be Ready"). Deleting destroys the workspace, so that stays
            # a deliberate act by the caller, never an automatic recovery.
            echo "sandbox '$name' is in the Error phase, which cannot be started or" >&2
            echo "stopped. Its workspace is unrecoverable. To rebuild it:" >&2
            echo "    openshell sandbox delete $name && os $name" >&2
            return 1
            ;;
        *)
            echo "sandbox '$name' is in an unexpected phase: $phase" >&2
            return 1
            ;;
    esac
}
alias os='openshell-session'
alias osl='openshell sandbox list'
