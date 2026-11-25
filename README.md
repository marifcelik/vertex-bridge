# vertex-bridge

Lightweight, zero-dependency Go reverse proxy that bridges **native Gemini API** clients (like [Crush](https://github.com/charmbracelet/crush)) to **Google Cloud Vertex AI / Gemini Enterprise Agent Platform** using a Vertex AI API key (`x-goog-api-key`).

## Why?

- Gemini 4 models require preserving `thought_signature` across multi-turn tool calls (`functionCall` / `functionResponse`).
- Many OpenAI-compatible client layers drop `thought_signature`, causing `400 INVALID_ARGUMENT` errors during tool calling.
- Native Gemini API clients preserve `thought_signature`, but send requests to `/v1beta/models/<model>:streamGenerateContent` and include `functionCall.id` / `functionResponse.id` fields that Vertex AI rejects.

`vertex-bridge` solves both:
1. Rewrites `/v1beta/models/...` (and `/v1/models/...`) to `/v1beta1/projects/<project>/locations/<location>/publishers/google/models/...` on `https://aiplatform.googleapis.com`.
2. Strips Vertex-incompatible `id` fields from `functionCall` and `functionResponse` parts while keeping `thoughtSignature` intact.
3. Streams SSE responses immediately (`FlushInterval: -1`).

## Quick Install

### One-liner (Linux / macOS, requires Go)

```bash
curl -fsSL https://raw.githubusercontent.com/marifcelik/vertex-bridge/main/install.sh | bash -s -- --project YOUR_GCP_PROJECT_ID
```

### From a local clone

```bash
git clone https://github.com/marifcelik/vertex-bridge.git
cd vertex-bridge
./install.sh --project YOUR_GCP_PROJECT_ID --location global --listen 127.0.0.1:8788
```

On Linux with `systemd`, `install.sh` builds `~/.local/bin/vertex-bridge` and installs/enables `~/.config/systemd/user/vertex-bridge.service` automatically. Pass `--no-systemd` to install the binary only.

## Usage

```bash
vertex-bridge -project YOUR_GCP_PROJECT_ID -location global -listen 127.0.0.1:8788
```

Environment variables are also supported:
- `VERTEX_PROJECT` (required if `-project` is not passed)
- `VERTEX_LOCATION` (default: `global`)
- `VERTEX_LISTEN` (default: `127.0.0.1:8788`)

## Crush Configuration Example (`~/.config/crush/crush.json`)

```json
{
  "providers": {
    "gemini": {
      "api_key": "$VERTEX_API_KEY",
      "base_url": "http://127.0.0.1:8788",
      "type": "google",
      "models": [
        {
          "id": "gemini-4-carbon",
          "name": "Gemini 4 Carbon",
          "context_window": 1048576,
          "default_max_tokens": 65536,
          "pricing": { "input": 2, "output": 10, "cache_hit": 0.1 },
          "capabilities": { "vision": true },
          "reasoning": {
            "thinking": "toggleable",
            "default_effort_level": "medium",
            "effort_levels": [
              { "display": "Low", "value": "low" },
              { "display": "Medium", "value": "medium" },
              { "display": "High", "value": "high" }
            ]
          }
        }
      ]
    }
  }
}
```

## License

MIT
