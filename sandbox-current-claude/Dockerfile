# OpenShell sandbox with a current Claude Code.
#
#   openshell sandbox create \
#     --from   /path/to/openshell-agent/sandbox-current-claude \
#     --policy /path/to/openshell-agent/sandbox-policy.yaml \
#     -- claude
#
# Why this image exists: ghcr.io/nvidia/openshell-community/sandboxes/base:latest is a
# 2026-05-29 build and upstream has not rebuilt it since (checked 2026-09-07 -- `latest`
# and the newest tag fffb6b2 are the same digest). It ships Claude Code 2.1.156 at
# /usr/local/bin/claude, which predates Opus 5, so the model picker tops out at Opus 4.8.
# Pulling cannot fix that; installing over it can.
#
# npm's prefix in this image is /usr, so `npm install -g` writes the launcher to
# /usr/bin/claude. The stale 240MB /usr/local/bin/claude sits earlier on PATH and would
# shadow it, so repoint that path at the new install rather than leaving two copies.
#
# The install runs at BUILD time, where egress is unrestricted -- it does not depend on
# the sandbox network policy. sandbox-policy.yaml separately unblocks downloads.claude.ai
# so that `claude update` also works from inside a running sandbox.
FROM ghcr.io/nvidia/openshell-community/sandboxes/base:latest
USER root
RUN npm install -g @anthropic-ai/claude-code@latest \
    && ln -sf /usr/bin/claude /usr/local/bin/claude \
    && claude --version
USER sandbox
