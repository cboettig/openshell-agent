# openshell-agent

Our standard [OpenShell](https://github.com/nvidia/openshell) sandbox: R, Python and CUDA
from [rocker/ml](https://rocker-project.org), a current Claude Code, a network policy that
lets it stay current, and shell helpers for getting in and out.

Sandboxes follow the upstream
[community](https://github.com/NVIDIA/OpenShell-Community) layout — one directory per
sandbox holding a `Dockerfile` and a `policy.yaml`:

| path | what it is |
| --- | --- |
| `sandboxes/rocker/Dockerfile` | rocker/ml + Claude Code + the supervisor's prerequisites |
| `sandboxes/rocker/policy.yaml` | network/filesystem policy; replaces the built-in default |
| `aliases.sh` | the `os` / `osl` shell helpers |

## Setup

```bash
echo '. /path/to/openshell-agent/aliases.sh' >> ~/.bash_aliases
```

`aliases.sh` locates the repo from its own path, so a checkout anywhere works. Set
`OPENSHELL_AGENT_DIR` to override.

## Usage

```bash
os                # shell in `dev`, creating it on first use
os scratch        # a second, separate sandbox
os dev -- claude  # Claude Code as the main process instead of a shell
osl               # list sandboxes
```

`os` dispatches on the sandbox's phase, so the same command works whether the sandbox is
running, stopped, or doesn't exist yet. The equivalent raw commands:

```bash
# create -- only when the sandbox does not exist. Omitting `--` leaves openshell to
# pick its own default shell; anything after `--` becomes the main process.
openshell sandbox create \
  --name   dev \
  --from   ./sandboxes/rocker \
  --policy ./sandboxes/rocker/policy.yaml \
  [-- claude]

# already running (phase Ready) -- attach to the existing main process
openshell sandbox connect dev

# phase Stopped or Error -- the workspace is intact, just bring it back
openshell sandbox start dev && openshell sandbox connect dev

# what `os` reads to decide which of the three to run
openshell sandbox get dev -o json    # -> .phase
openshell sandbox list               # == osl
```

### Detach, don't exit

Exiting the main process stops the container, and OpenShell then reports the sandbox as
**`Error`** rather than `Stopped`. That is what the `Error` phase means — not a crash. Use
**Ctrl-P Ctrl-Q** to detach and leave it running. `start` recovers either state without
losing the workspace, including the Claude Code login.

## Why a derived image

`rocker/ml` gives us the R, Python and CUDA stack we actually work in, but it is not an
OpenShell base image and ships no Claude Code. `sandboxes/rocker/Dockerfile` adds three
things: the supervisor's prerequisites (`iproute2`, `nftables`, `iptables`, `dnsutils`,
`openssh-sftp-server` — without them netns bring-up degrades and bypass detection cannot
install), the `sandbox` and `supervisor` users the privilege drop targets, and Node 22
with a current Claude Code.

It also overrides rocker's `HOME=/home/jovyan`. Left alone that beats the passwd entry, and
Claude Code writes its credential somewhere the sandbox user cannot write and that is not
part of the persisted workspace.

The upstream community base is not an option: it was last built 2026-05-29 and has not been
rebuilt since — `latest` and the newest tag `fffb6b2` are the same digest — so it ships
Claude Code 2.1.156, which predates Opus 5.

`policy.yaml` separately unblocks `downloads.claude.ai` so `claude update` also
works from *inside* a running sandbox. Without it the native updater fails silently, and
the only trace is `$HOME/.claude/.last-update-result.json`:

```json
{"path":"native","outcome":"failed","status":"install_failed",
 "version_from":"2.1.156","version_to":null}
```

The policy also adds the paths npm actually installs to. `npm install -g` resolves through
to `/usr/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe`, a **native** binary —
the stock allowlist's `/usr/bin/node` does not cover it, and without a matching entry the
new install is denied at the proxy.

## Everything is pinned at create time

A sandbox binds to its image, its supervisor binary, and its policy when it is **created**,
and never re-resolves any of them. Neither `docker pull`, nor upgrading the `openshell`
package, nor editing `policy.yaml` affects a sandbox that already exists —
`sandbox stop`/`start` reuses the same container. Only a fresh `sandbox create` picks up
new versions. Treat sandboxes as disposable and keep state in the workspace.

Upgrade ritual:

```bash
# 1. openshell itself -- nothing auto-updates
openshell --version

# 2. re-capture the built-in default policy and diff it against ours, so upstream
#    additions don't silently go missing (--policy REPLACES the default outright)
openshell policy get <sandbox> --base -o json

# 3. rebuild and recreate
docker pull rocker/ml:latest
openshell sandbox delete dev && os
```

Adding a sandbox means a new `sandboxes/<name>/` with its own `Dockerfile` and
`policy.yaml`; point `os` at it with `--from`/`--policy`, or set `OPENSHELL_SANDBOX`.

## Auth

Claude Code in the sandbox authenticates with an OAuth credential file under the sandbox
user's `$HOME` (`/sandbox`), which is the persisted workspace. Nothing is injected from the
host — no `openshell provider`, no bind-mounted credential, no API key in the environment.
So `stop`/`start`, and `-- claude` vs. a shell, make no difference; but a **new** sandbox
means a fresh `/sandbox` and therefore a new login.
