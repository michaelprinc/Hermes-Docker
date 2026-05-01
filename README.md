# Hermes Docker Runtime

This module packages Hermes Agent for the current workspace in the same
`Sync -> Start -> Test` operator flow already used by `openclaw-docker`.

It is intentionally narrower than the upstream Hermes deployment docs:

- runtime is pinned through a local wrapper image built from the official
  `nousresearch/hermes-agent` image
- model selection is parameterized for `Configured`, `Codex`, and `Local`
- Discord configuration is prepared but disabled by default
- generated Hermes home files live under `hermes-docker/runtime/bootstrap`
  and are copied into the persistent Docker volume on container startup

## Prerequisites

- Docker Desktop with Compose support
- optional local OpenAI-compatible endpoint for Gemma, for example
  `http://host.docker.internal:8014/v1`
- Hermes credentials only when you want live Codex conversations; the Docker
  runtime itself can be built and validated without Discord or Codex secrets

## Quick Start

1. Copy `hermes-docker/.env.example` to `hermes-docker/.env`.
2. Sync runtime files:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\hermes-docker\scripts\Sync-HermesDockerConfig.ps1 -Verbose
```

3. Start the container:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\hermes-docker\scripts\Start-HermesDockerGateway.ps1 -Verbose
```

4. Verify the runtime:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\hermes-docker\scripts\Test-HermesDockerGateway.ps1 -Verbose
```

## Model Modes

`Configured`

- uses `.env` values `HERMES_MODEL_PROVIDER`, `HERMES_MODEL_DEFAULT`,
  `HERMES_MODEL_BASE_URL`, and `HERMES_MODEL_API_KEY`

`Codex`

- forces `provider: openai-codex`
- uses `HERMES_CODEX_MODEL` as the model name
- live requests still need Hermes-side Codex auth in the persistent Hermes home

`Local`

- forces `provider: custom`
- points Hermes to `HERMES_LOCAL_MODEL_BASE_URL`
- uses `HERMES_LOCAL_MODEL_ID` and `HERMES_LOCAL_MODEL_API_KEY`

Example for local Gemma 4:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\hermes-docker\scripts\Start-HermesDockerGateway.ps1 `
  -ModelMode Local `
  -LocalModelBaseUrl "http://host.docker.internal:8014/v1" `
  -LocalModelId "Gemma-4-26B-A4B-it-Q4_K_S" `
  -Verbose
```

## Discord

The generated runtime always prepares the Discord section in `config.yaml`, but
keeps `DISCORD_BOT_TOKEN` empty and `HERMES_DISCORD_ENABLED=false` by default.
That means the runtime is structurally ready for a later Discord hookup without
activating it in this MVP.

## Upstream Notes

The implementation follows the official Hermes project shape verified on
2026-04-30:

- upstream image: `nousresearch/hermes-agent`
- upstream runtime state: `/opt/data`
- Windows is not a supported native host for Hermes itself, but Linux Docker
  containers are supported and fit the current workspace model