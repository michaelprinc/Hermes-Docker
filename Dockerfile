ARG HERMES_BASE_IMAGE=nousresearch/hermes-agent:latest
FROM ${HERMES_BASE_IMAGE}

COPY hermes-docker/docker-entrypoint.sh /usr/local/bin/hermes-docker-entrypoint

USER root
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl gnupg python3-pip; \
    . /etc/os-release; \
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -; \
    apt-get install -y --no-install-recommends nodejs; \
    case "$ID" in \
      ubuntu) ms_repo_url="https://packages.microsoft.com/config/ubuntu/${VERSION_ID}/packages-microsoft-prod.deb" ;; \
      debian) ms_repo_url="https://packages.microsoft.com/config/debian/${VERSION_ID}/packages-microsoft-prod.deb" ;; \
      *) echo "Unsupported base image for PowerShell install: $ID $VERSION_ID" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "$ms_repo_url" -o /tmp/packages-microsoft-prod.deb; \
    dpkg -i /tmp/packages-microsoft-prod.deb; \
    rm -f /tmp/packages-microsoft-prod.deb; \
    apt-get update; \
    apt-get install -y --no-install-recommends powershell; \
    PIP_BREAK_SYSTEM_PACKAGES=1 npm install -g --legacy-peer-deps pylance-mcp-server@1.1.0; \
    pwsh -NoLogo -NoProfile -NonInteractive -Command "Set-PSRepository -Name PSGallery -InstallationPolicy Trusted; Install-Module PSScriptAnalyzer -Scope AllUsers -Force"; \
    npm cache clean --force; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*; \
    chmod 755 /usr/local/bin/hermes-docker-entrypoint \
    && python3 -c "import json; from pathlib import Path; p = Path('/opt/hermes/package.json'); data = json.loads(p.read_text(encoding='utf-8')); data['type'] = 'module'; p.write_text(json.dumps(data, indent=2, ensure_ascii=True) + '\n', encoding='utf-8')" \
    && chown hermes:hermes /opt/hermes /opt/hermes/package.json /opt/hermes/README.md \
    && chown -R hermes:hermes /opt/hermes/.venv /opt/hermes/hermes_agent.egg-info /opt/hermes/hermes_cli/web_dist

ENTRYPOINT ["/usr/local/bin/hermes-docker-entrypoint"]
CMD ["gateway", "run"]
