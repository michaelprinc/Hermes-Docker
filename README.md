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

The PowerShell scripts read `hermes-docker/.env` for default model and runtime
settings. Explicit script parameters still win over `.env` values.

## Prerequisites

- Docker Desktop with Compose support
- local OpenAI-compatible endpoint for the selected model, exposed on the
  Windows host as `http://127.0.0.1:8068/v1`
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

## Build, Run, And Reinstall

Run these commands from `agent-platforms` in a PowerShell terminal. The compose
file is designed to keep Hermes runtime state in the `hermes_state` Docker
volume, so a normal rebuild/reinstall refreshes the image and containers
without deleting sessions, config, skills, or credentials.

### First Run

1. Prepare the local environment file if it does not exist yet:

```powershell
Copy-Item .\hermes-docker\.env.example .\hermes-docker\.env
```

2. Generate the runtime bootstrap files:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\hermes-docker\scripts\Sync-HermesDockerConfig.ps1 -Verbose
```

3. Build the Hermes wrapper image:

```powershell
docker compose --env-file .\hermes-docker\.env -f .\hermes-docker\docker-compose.yml build hermes-gateway
```

4. Start the gateway container:

```powershell
docker compose --env-file .\hermes-docker\.env -f .\hermes-docker\docker-compose.yml up -d hermes-gateway
```

5. Start the optional dashboard with the browser Chat tab:

```powershell
docker compose --env-file .\hermes-docker\.env -f .\hermes-docker\docker-compose.yml --profile dashboard up -d hermes-dashboard
```

6. Open the dashboard:

```text
http://127.0.0.1:9119
```

With Discord disabled, `hermes-gateway` still remains running under the
upstream Hermes supervision model and logs that no messaging platforms are
enabled. The optional dashboard service serves the browser UI and embedded
Chat tab.

### Reinstall With docker compose build

Use this when `Dockerfile`, `docker-entrypoint.sh`, `docker-compose.yml`, the
base image, or Hermes package state needs to be refreshed.

1. Stop the running Hermes containers:

```powershell
docker compose --env-file .\hermes-docker\.env -f .\hermes-docker\docker-compose.yml --profile dashboard stop hermes-gateway hermes-dashboard
```

2. Regenerate the runtime bootstrap files from `hermes-docker/.env`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\hermes-docker\scripts\Sync-HermesDockerConfig.ps1 -Verbose
```

3. Rebuild the local wrapper image:

```powershell
docker compose --env-file .\hermes-docker\.env -f .\hermes-docker\docker-compose.yml build --pull hermes-gateway
```

For a deeper rebuild that ignores Docker layer cache:

```powershell
docker compose --env-file .\hermes-docker\.env -f .\hermes-docker\docker-compose.yml build --pull --no-cache hermes-gateway
```

4. Recreate the gateway container from the rebuilt image:

```powershell
docker compose --env-file .\hermes-docker\.env -f .\hermes-docker\docker-compose.yml up -d --force-recreate hermes-gateway
```

5. Verify the gateway before starting the dashboard:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\hermes-docker\scripts\Test-HermesDockerGateway.ps1 -Verbose
```

6. Recreate the optional dashboard after the gateway is healthy:

```powershell
docker compose --env-file .\hermes-docker\.env -f .\hermes-docker\docker-compose.yml --profile dashboard up -d --force-recreate hermes-dashboard
```

Starting the dashboard only after the gateway is stable avoids transient
startup races while the shared `hermes_state` volume is being migrated or
chowned by the upstream Hermes image.

7. Verify container state and port bindings:

```powershell
docker compose --env-file .\hermes-docker\.env -f .\hermes-docker\docker-compose.yml --profile dashboard ps -a
```

The dashboard `PORTS` column should show `127.0.0.1:9119->9119/tcp`.

8. Verify the gateway and, when the dashboard is running, the dashboard Chat
   tab:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\hermes-docker\scripts\Test-HermesDockerGateway.ps1 -Verbose
```

9. Check recent logs if startup fails:

```powershell
docker compose --env-file .\hermes-docker\.env -f .\hermes-docker\docker-compose.yml logs --tail 100 hermes-gateway
docker compose --env-file .\hermes-docker\.env -f .\hermes-docker\docker-compose.yml logs --tail 100 hermes-dashboard
```

Do not use `docker compose down -v` for a normal reinstall. The `-v` switch
deletes the `hermes_state` volume and removes persisted Hermes runtime data.

## Startup Auto-Update

The wrapper entrypoint runs `hermes update --yes --gateway` before each
container start, so the Hermes Agent package and the components managed by the
Hermes updater are refreshed whenever `hermes-gateway` or `hermes-dashboard`
starts.

Relevant `.env` switches:

```env
HERMES_AUTO_UPDATE=true
HERMES_AUTO_UPDATE_ARGS=--yes --gateway
HERMES_AUTO_UPDATE_REQUIRED=false
UV_LINK_MODE=copy
```

Set `HERMES_AUTO_UPDATE=false` to skip the startup update. Set
`HERMES_AUTO_UPDATE_REQUIRED=true` when a failed update should stop the
container instead of continuing with the installed version.

The wrapper normalizes Hermes package ownership before the update and runs the
updater as the `hermes` user, so files under `/opt/hermes/.venv` remain writable
across image rebuilds and package upgrades.

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

Default local endpoint from Docker is `http://host.docker.internal:8068/v1`.
The local server must expose an OpenAI-compatible API, including `/v1/models`
and `/v1/chat/completions`.

Example for the current local Qwen endpoint:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\hermes-docker\scripts\Start-HermesDockerGateway.ps1 `
  -ModelMode Local `
  -LocalModelBaseUrl "http://host.docker.internal:8068/v1" `
  -LocalModelId "qwen36_35b_a3b_mtp_iq3xxs_rx6800_cache_mtp_256k" `
  -Verbose
```

## VS Code Usage

Hermes can be reached through several interfaces after the Docker container is
running. The default Docker command starts `hermes gateway run`, which keeps the
messaging gateway process alive and publishes container port `8642`. That port
is for gateway integrations; it is not a browser chat UI by itself. With
Discord disabled, the gateway logs will say that no messaging platforms are
enabled.

Available interfaces in this Docker profile:

| Interface | How to use it | Notes |
|-----------|---------------|-------|
| CLI chat | `docker compose exec hermes-gateway sh -lc 'export VIRTUAL_ENV=/opt/hermes/.venv; export PATH="$VIRTUAL_ENV/bin:$PATH"; /opt/hermes/hermes chat'` | Best for manual use from the VS Code terminal. |
| One-shot CLI | `hermes chat -q "..."` or `hermes -z "..."` inside the container | Best for scripts and quick checks. |
| ACP server | `docker compose exec hermes-gateway sh -lc 'export VIRTUAL_ENV=/opt/hermes/.venv; export PATH="$VIRTUAL_ENV/bin:$PATH"; /opt/hermes/hermes acp'` | Editor integration protocol for VS Code, Zed, and JetBrains. Requires the ACP extra dependencies in the image. |
| Web dashboard | `docker compose --profile dashboard up -d hermes-dashboard` | Browser UI with the Chat tab on `http://127.0.0.1:9119`, published only to localhost on the Windows host. |
| MCP server | `hermes mcp serve` inside the container | Exposes Hermes conversations to MCP clients; configure the client to launch it through Docker. |
| Messaging gateway | Default container command: `gateway run` | Supports Telegram, Discord, WhatsApp, Slack/Weixin-style integrations when configured. Disabled by default here. |

### Terminal Workflow

1. Open this repository in VS Code and use a PowerShell terminal from
   `agent-platforms`.
2. Make sure the local model server is already running on
   `http://127.0.0.1:8068/v1`.
3. Sync and start Hermes:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\hermes-docker\scripts\Sync-HermesDockerConfig.ps1 -Verbose
powershell -NoProfile -ExecutionPolicy Bypass -File .\hermes-docker\scripts\Start-HermesDockerGateway.ps1 -Verbose
```

4. Verify the container:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\hermes-docker\scripts\Test-HermesDockerGateway.ps1 -Verbose
```

5. Verify that the persistent Hermes home inside Docker uses the local Windows
   model endpoint:

```powershell
docker compose --env-file .\hermes-docker\.env -f .\hermes-docker\docker-compose.yml exec -T hermes-gateway sh -lc 'export VIRTUAL_ENV=/opt/hermes/.venv; export PATH="$VIRTUAL_ENV/bin:$PATH"; /opt/hermes/hermes config'
```

The `Model` section must include:

```text
provider: custom
base_url: http://host.docker.internal:8068/v1
default: qwen36_35b_a3b_mtp_iq3xxs_rx6800_cache_mtp_256k
```

Run a one-shot prompt through Hermes to confirm that the agent itself can use
the local model:

```powershell
docker compose --env-file .\hermes-docker\.env -f .\hermes-docker\docker-compose.yml exec -T hermes-gateway sh -lc 'export VIRTUAL_ENV=/opt/hermes/.venv; export PATH="$VIRTUAL_ENV/bin:$PATH"; /opt/hermes/hermes -z "Reply with exactly LOCAL_OK" --provider custom -m qwen36_35b_a3b_mtp_iq3xxs_rx6800_cache_mtp_256k'
```

6. Inspect logs or run the bundled CLI:

```powershell
docker compose --env-file .\hermes-docker\.env -f .\hermes-docker\docker-compose.yml logs -f hermes-gateway
docker compose --env-file .\hermes-docker\.env -f .\hermes-docker\docker-compose.yml exec hermes-gateway sh -lc 'export VIRTUAL_ENV=/opt/hermes/.venv; export PATH="$VIRTUAL_ENV/bin:$PATH"; /opt/hermes/hermes version'
```

7. Start an interactive chat from the VS Code terminal:

```powershell
docker compose --env-file .\hermes-docker\.env -f .\hermes-docker\docker-compose.yml exec hermes-gateway sh -lc 'export VIRTUAL_ENV=/opt/hermes/.venv; export PATH="$VIRTUAL_ENV/bin:$PATH"; /opt/hermes/hermes chat'
```

For a single prompt:

```powershell
docker compose --env-file .\hermes-docker\.env -f .\hermes-docker\docker-compose.yml exec -T hermes-gateway sh -lc 'export VIRTUAL_ENV=/opt/hermes/.venv; export PATH="$VIRTUAL_ENV/bin:$PATH"; /opt/hermes/hermes chat -q "Summarize the current repository architecture."'
```

### VS Code Editor Integration

Hermes exposes ACP for editor integration. The Docker image already reports
`Hermes ACP check OK` with:

```powershell
docker compose --env-file .\hermes-docker\.env -f .\hermes-docker\docker-compose.yml exec -T hermes-gateway sh -lc 'export VIRTUAL_ENV=/opt/hermes/.venv; export PATH="$VIRTUAL_ENV/bin:$PATH"; /opt/hermes/hermes acp --check'
```

For a VS Code ACP-capable extension, configure the agent command as a Docker
Compose exec command that launches ACP:

```powershell
docker compose --env-file .\hermes-docker\.env -f .\hermes-docker\docker-compose.yml exec -T hermes-gateway sh -lc 'export VIRTUAL_ENV=/opt/hermes/.venv; export PATH="$VIRTUAL_ENV/bin:$PATH"; /opt/hermes/hermes acp --accept-hooks'
```

Use `-T` for protocol clients because ACP communicates over stdio and should
not allocate an interactive TTY.

### Optional Dashboard

The dashboard exposes Hermes configuration, sessions, and API-key settings, so
do not publish it on `0.0.0.0` or a LAN-facing address. The compose file uses a
separate `dashboard` profile and binds the host port to `127.0.0.1` only:

```yaml
ports:
  - "127.0.0.1:${HERMES_DASHBOARD_PORT}:9119"
```

Hermes still has to bind to `0.0.0.0` inside the container so Docker can forward
traffic from the host. The service therefore passes `--insecure`, but the
external exposure is constrained by Docker to the local PC only. Do not change
the port mapping to `9119:9119`.

The dashboard service also passes `--tui` and sets `HERMES_DASHBOARD_TUI=1`.
Hermes uses that flag to expose the embedded browser Chat tab.

Start the localhost-only dashboard:

```powershell
docker compose --env-file .\hermes-docker\.env -f .\hermes-docker\docker-compose.yml --profile dashboard up -d hermes-dashboard
```

Then open `http://127.0.0.1:9119` on the host.

Verify that Docker did not publish the dashboard externally:

```powershell
docker compose --env-file .\hermes-docker\.env -f .\hermes-docker\docker-compose.yml ps hermes-dashboard
```

The `PORTS` column must show `127.0.0.1:9119->9119/tcp`, not
`0.0.0.0:9119->9119/tcp`.

Stop the dashboard when it is not needed:

```powershell
docker compose --env-file .\hermes-docker\.env -f .\hermes-docker\docker-compose.yml --profile dashboard stop hermes-dashboard
```

### Tailscale Access

Keep the Docker dashboard port bound to `127.0.0.1` and expose it to trusted
tailnet devices with Tailscale Serve:

```powershell
& 'C:\Program Files\Tailscale\tailscale.exe' serve --http=9119 --yes --bg 9119
```

Then open the MagicDNS URL from another tailnet device:

```text
http://desktop-hcejv25.tail0dc8a8.ts.net:9119/
```

Use the MagicDNS hostname rather than the raw Tailscale IP because Tailscale
Serve routes HTTP by hostname. Inspect or remove the proxy with:

```powershell
& 'C:\Program Files\Tailscale\tailscale.exe' serve status
& 'C:\Program Files\Tailscale\tailscale.exe' serve --http=9119 off
```

### Persistent Config

Hermes stores runtime state in the `hermes_state` Docker volume. This Docker
profile is managed from repository files, so `HERMES_BOOTSTRAP_FORCE=true` is
set in `runtime/hermes.runtime.env` during sync. On container startup,
`runtime/bootstrap/config.yaml` is copied into `/opt/data/config.yaml`; this
prevents an older persistent volume from silently keeping a stale provider such
as `auto` or `gpt-5.4`.

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
