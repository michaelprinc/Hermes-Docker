ARG HERMES_BASE_IMAGE=nousresearch/hermes-agent:latest
FROM ${HERMES_BASE_IMAGE}

COPY hermes-docker/docker-entrypoint.sh /usr/local/bin/hermes-docker-entrypoint

USER root
RUN chmod 755 /usr/local/bin/hermes-docker-entrypoint

ENTRYPOINT ["/usr/local/bin/hermes-docker-entrypoint"]
CMD ["gateway", "run"]