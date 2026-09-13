# OpenShell "compute" sandbox: the geospatial stack, preinstalled, with no
# package-fetch egress at runtime.
#
#   openshell sandbox create --from ./sandboxes/compute --policy ./sandboxes/compute/policy.yaml
#
# The posture: everything is expected to be in the image already, so policy.yaml
# grants no package-fetch endpoints at all. Installing at runtime would mean CRAN,
# PyPI and github.com reachable and a package's configure script running arbitrary
# code as the sandbox user; policy-open.yaml restores that deliberately when you are
# still discovering dependencies, and it works on a running sandbox.
#
# rocker/ml-spatial is the base precisely so there is no package list to keep:
# it already carries the R/Python geospatial stack (GDAL, PROJ, GEOS, sf, terra,
# stars) on top of rocker/ml's R + Python + CUDA. When something is genuinely
# missing, add it HERE and rebuild -- that is the intended friction, and it is
# also where r2u still works, since these layers run as root.
FROM rocker/ml-spatial:latest

USER root
ENV DEBIAN_FRONTEND=noninteractive

# 1. Supervisor prerequisites. Not optional: the supervisor shells out to `ip`
#    and `nft` to build the sandbox network namespace and `sftp-server` backs
#    upload/download. A stock rocker image without these dies during
#    provisioning with ContainerExited -- measured, not assumed.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl dnsutils iproute2 iptables nftables \
        iputils-ping net-tools netcat-openbsd openssh-sftp-server \
        procps traceroute \
    && rm -rf /var/lib/apt/lists/*

# 2. The users the supervisor drops privileges to. `run_as_user` accepts the
#    literal name `sandbox` or a numeric uid >= 1 -- never 0, so nothing in this
#    sandbox can be root, and `no_new_privs` is set besides. sudo and apt are
#    therefore unavailable at runtime by design, which is why installation
#    belongs in the layers above.
RUN groupadd -r supervisor \
    && useradd -r -g supervisor -s /usr/sbin/nologin supervisor \
    && groupadd -r sandbox \
    && useradd -r -g sandbox -d /sandbox -s /bin/bash sandbox \
    && mkdir -p /sandbox && chown sandbox:sandbox /sandbox

# 3. Node 22 and a current Claude Code. npm's prefix here is /usr, so the launcher
#    lands at /usr/bin/claude -- resolving to a native claude.exe under
#    /usr/lib/node_modules/@anthropic-ai/, which policy.yaml allowlists explicitly.
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && npm install -g @anthropic-ai/claude-code@latest \
    && rm -rf /var/lib/apt/lists/* \
    && claude --version

# 4. OpenShell builds a fresh environment for exec'd processes and discards the
#    image's ENV, so rocker's PATH and VIRTUAL_ENV do not survive and its Python
#    is reachable only at its full path. A profile.d drop-in is read by the
#    shell itself, so it does survive.
#    A writable venv under /sandbox layered on rocker's, so pip has somewhere to
#    install: /opt is read-only, and without this `pip install` downloads the wheel
#    and then dies on EACCES. --system-site-packages keeps every preinstalled
#    package visible. The path is /sandbox/.venv because the stock policy already
#    allowlists /sandbox/.venv/bin/{python,pip} as pypi binaries.
#    Note --system-site-packages is not enough on its own: /opt/venv is itself a
#    venv whose `home = /usr/bin`, so a child venv's "system" resolves to /usr and
#    rocker's packages stay invisible. The .pth appends them explicitly, after the
#    local site-packages, so a locally installed package shadows the image's.
RUN python3 -m venv --system-site-packages /sandbox/.venv \
    && SP="$(/sandbox/.venv/bin/python3 -c 'import site; print(site.getsitepackages()[0])')" \
    && /opt/venv/bin/python3 -c 'import site; print(site.getsitepackages()[0])' \
         > "$SP/00-rocker-venv.pth" \
    && chown -R sandbox:sandbox /sandbox/.venv

RUN printf 'export PATH=/sandbox/.venv/bin:/opt/venv/bin:$PATH\nexport VIRTUAL_ENV=/sandbox/.venv\n' \
      > /etc/profile.d/10-rocker-venv.sh \
    && chmod 0644 /etc/profile.d/10-rocker-venv.sh

# 5. Runtime R settings. bspm routes install.packages() through `sudo apt-get`
#    for r2u binaries, which cannot work here (no root, no_new_privs), so turn
#    it off rather than let it fail confusingly. R_LIBS_USER points at the
#    writable workspace so an ad-hoc install has somewhere to land -- it simply
#    has nowhere to fetch from, which is the point.
RUN printf '\n# OpenShell: no root at runtime, so r2u/apt is unavailable.\noptions(bspm.sudo = FALSE)\n' \
      >> /usr/lib/R/etc/Rprofile.site \
    && printf 'R_LIBS_USER=/sandbox/R/library\n' >> /usr/lib/R/etc/Renviron.site \
    && mkdir -p /sandbox/R/library && chown -R sandbox:sandbox /sandbox/R

# No ENV HOME here: OpenShell discards the image's environment, and HOME comes
# from the passwd entry `useradd -d /sandbox` creates. Setting it was dead code.
WORKDIR /sandbox
USER sandbox
