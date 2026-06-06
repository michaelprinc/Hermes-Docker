ARG HERMES_BASE_IMAGE=nousresearch/hermes-agent:latest
FROM ${HERMES_BASE_IMAGE}

COPY hermes-docker/docker-entrypoint.sh /usr/local/bin/hermes-docker-entrypoint

USER root
RUN chmod 755 /usr/local/bin/hermes-docker-entrypoint \
    && python3 -c "import json; from pathlib import Path; p = Path('/opt/hermes/package.json'); data = json.loads(p.read_text(encoding='utf-8')); data['type'] = 'module'; p.write_text(json.dumps(data, indent=2, ensure_ascii=True) + '\n', encoding='utf-8')" \
    && chown hermes:hermes /opt/hermes /opt/hermes/package.json /opt/hermes/README.md \
    && chown -R hermes:hermes /opt/hermes/.venv /opt/hermes/hermes_agent.egg-info /opt/hermes/hermes_cli/web_dist

ENTRYPOINT ["/usr/local/bin/hermes-docker-entrypoint"]
CMD ["gateway", "run"]
