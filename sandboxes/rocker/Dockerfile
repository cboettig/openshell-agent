# OpenShell sandbox on the Rocker ML image: R, Python and CUDA, plus a current
# Claude Code and the pieces the OpenShell supervisor needs.
#
#   openshell sandbox create --from ./sandboxes/rocker --policy ./sandboxes/rocker/policy.yaml
#
# rocker/ml ships neither Node nor Claude Code, and like most general-purpose
# images it lacks the supervisor's prerequisites -- so this adds three things.
FROM rocker/ml:latest

USER root
ENV DEBIAN_FRONTEND=noninteractive

# 1. Supervisor prerequisites, matching NVIDIA/OpenShell-Community sandboxes/base.
#    iproute2/iptables/nftables set up and police the sandbox network namespace;
#    without them the netns bring-up degrades and bypass detection cannot install.
#    openssh-sftp-server backs `openshell sandbox upload`/`download`.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        dnsutils \
        iproute2 \
        iptables \
        nftables \
        iputils-ping \
        net-tools \
        netcat-openbsd \
        openssh-sftp-server \
        procps \
        traceroute \
    && rm -rf /var/lib/apt/lists/*

# 2. The users the supervisor drops privileges to. `sandbox` owns the workspace at
#    /sandbox, which is the only read-write path in policy.yaml and the home the
#    Claude Code credential lands in.
RUN groupadd -r supervisor \
    && useradd -r -g supervisor -s /usr/sbin/nologin supervisor \
    && groupadd -r sandbox \
    && useradd -r -g sandbox -d /sandbox -s /bin/bash sandbox \
    && mkdir -p /sandbox \
    && chown sandbox:sandbox /sandbox

# 3. Node 22 and a current Claude Code. npm's prefix here is /usr, so the launcher
#    lands at /usr/bin/claude -- resolving to a native claude.exe under
#    /usr/lib/node_modules/@anthropic-ai/, which policy.yaml allowlists explicitly.
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && npm install -g @anthropic-ai/claude-code@latest \
    && rm -rf /var/lib/apt/lists/* \
    && claude --version

# rocker sets HOME=/home/jovyan for its own default user. Left alone it overrides the
# passwd entry, and Claude Code would write its credential to a directory the sandbox
# user cannot write and that is not part of the persisted workspace.
ENV HOME=/sandbox

WORKDIR /sandbox
USER sandbox
