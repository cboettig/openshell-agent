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
  --tty \
  [-- claude]

# already running (phase Ready) -- open a new shell on a fresh pty
openshell sandbox exec -n dev --tty -- bash -l

# phase Stopped -- the workspace is intact, just bring it back. (Phase Error cannot be
# started or stopped; it is unrecoverable, see "Detach, don't exit" below.)
openshell sandbox start dev && openshell sandbox exec -n dev --tty -- bash -l

# what `os` reads to decide which of the three to run
openshell sandbox get dev -o json    # -> .phase
openshell sandbox list               # == osl
```

### `connect` vs `exec --tty`

`openshell sandbox connect` reattaches to the sandbox's *canonical main process*. If that
process was launched without a pty — which is what you get unless `create` saw a terminal
on both stdin and stdout — it never became an interactive shell, so reattaching gives you
no prompt, no echo and no line editing. It still runs whatever you type, silently, which
reads exactly like `connect` hanging. Confirm it with `cat /proc/<pid>/stat` on the main
process: `tty_nr=0` means no controlling terminal.

`exec --tty` sidesteps this by allocating a fresh pty for a new process, so `os` uses that
to attach to an already-running sandbox. It also means exiting that shell only ends the
`exec`, leaving the sandbox up.

### Detach, don't exit

This applies to the main process only — the shell you land in on `create`. Exiting it stops
the container, and OpenShell then reports the sandbox as **`Error`** rather than `Stopped`.
That is what the `Error` phase means — not a crash. Use **Ctrl-P Ctrl-Q** to detach and
leave it running.

**`Error` is terminal.** `start` refuses it (*"sandbox must be Stopped to start"*) and so
does `stop` (*"must be Ready to stop"*), so there is no way back: the workspace and the
Claude Code login are gone and the only recovery is `sandbox delete` + a fresh `create`.
Only a sandbox you actually stopped, via `openshell sandbox stop`, comes back with `start`.
That makes Ctrl-P Ctrl-Q the difference between keeping a sandbox and rebuilding it.

## Why a derived image

`rocker/ml` gives us the R, Python and CUDA stack we actually work in, but it is not an
OpenShell base image and ships no Claude Code. `sandboxes/rocker/Dockerfile` adds three
things: the supervisor's prerequisites (`iproute2`, `nftables`, `iptables`, `dnsutils`,
`openssh-sftp-server` — the supervisor shells out to `ip` and `nft` to build the sandbox
network namespace, and `sftp-server` backs `sandbox upload`/`download`), the `sandbox` and
`supervisor` users the privilege drop targets, and Node 22 with a current Claude Code.

A `CONFIG:DEGRADED — Failed to install bypass detection rules` warning at startup is
**host-side, not image-side**: the `nft ... reject with icmp type port-unreachable` rule
needs `nft_reject_inet` loaded on the host. Upstream's base image hits it too. It is
non-fatal — proxy enforcement is unaffected, only the diagnostic that flags direct
connection attempts. Clear it with `sudo modprobe nft_reject_inet`.

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

A sandbox binds to its image and its supervisor binary when it is **created**, and never
re-resolves either. Neither `docker pull` nor upgrading the `openshell` package affects a
sandbox that already exists — `sandbox stop`/`start` reuses the same container. Only a
fresh `sandbox create` picks up new versions. Treat sandboxes as disposable and keep state
in the workspace.

**Policy is the exception.** Editing `policy.yaml` does not reach a running sandbox by
itself, but `openshell policy set <sandbox> --policy <file> --wait` pushes a new revision
to a live one and the supervisor loads it (the CLI reports the version and hash it
activated). Useful for tightening a long-running sandbox mid-session, and for iterating on
a policy without paying for a rebuild.

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

## Credentials the sandbox never holds

A `openshell provider` keeps a secret at the gateway and puts only a **placeholder** in the
sandbox environment:

```
api_token=openshell:resolve:env:v13489987411037355703_api_token
```

The proxy substitutes the real value **on egress, wherever it finds the placeholder in the
request**. It does not invent an `Authorization` header — the client has to send the
placeholder itself, which is the part that is easy to get wrong. Verified on 0.0.116
against GitHub:

```bash
# API: placeholder straight into the header
curl -H "Authorization: Bearer $api_token" https://api.github.com/user     # -> 200

# git: placeholder as the URL password, colons percent-encoded. The proxy sees through
# git's own base64 Basic encoding, so clone/fetch/push of a PRIVATE repo all work.
ENC=$(printf %s "$api_token" | sed 's/:/%3A/g')
git clone "https://x-access-token:$ENC@github.com/<owner>/<repo>.git"
```

A full container compromise therefore yields no token — only a placeholder that is useless
anywhere the policy does not already allow.

Two mechanics worth knowing before building on this:

- **A profile's `endpoints` do not compose into a custom `--policy`.** `--policy` replaces
  the built-in default outright, and provider-supplied endpoints do not reappear. Declare
  them in the policy yourself and point them at the credential with
  `credential_binding: {provider: <name>}`. That in turn requires a profile with
  `endpoints: []`, because a profile that declares its own endpoints refuses the binding
  (*"profile endpoints remain the credential boundary"*). Upstream
  [#2330](https://github.com/NVIDIA/OpenShell/issues/2330) proposes this credentials/
  endpoints split as a first-class feature; until then it is the manual recipe.
- **One host:port is one credential domain**, so one scoped credential per sandbox. See the
  header of `sandboxes/rocker/policy.yaml`.

`auth_style` in a profile (`bearer`, `basic`, …) does not change any of the above:
substitution is driven by finding the placeholder, not by the declared style.

## Auth

Claude Code in the sandbox authenticates with an OAuth credential file under the sandbox
user's `$HOME` (`/sandbox`), which is the persisted workspace. Nothing is injected from the
host for *this* credential — no `openshell provider`, no bind-mounted credential, no API
key in the environment (see above for credentials that do come from a provider).
So `stop`/`start`, and `-- claude` vs. a shell, make no difference; but a **new** sandbox
means a fresh `/sandbox` and therefore a new login.
