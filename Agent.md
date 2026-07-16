# Agent Deployment Notes & Tricks

## 1. Deployment Configuration

### Target Space
- **Profile:** `Leon4gr45`
- **Space:** `analytics`
- **Full Identifier:** `Leon4gr45/analytics`
- **Frontend Port:** `7860` (mandatory for all Hugging Face Spaces)

### Deployment Method
Choose the correct SDK based on the app type based on the codebase language:

- **Gradio SDK** — for Gradio applications
- **Streamlit SDK** — for Streamlit applications
- **Docker SDK** — for all other applications (recommended default for flexibility)

### HF Token
- The environment variable `HF_TOKEN` will always be provided at execution time.
- Never hardcode the token. Always read it from the environment.
- All monitoring and log‑streaming commands rely on `HF_TOKEN`.

### Required Files
- `Dockerfile` (or `app.py` for Gradio/Streamlit SDKs)
- `README.md` with Hugging Face YAML frontmatter:
  ```yaml
  ---
  title: Plausible Analytics
  emoji: 📈
  colorFrom: blue
  colorTo: indigo
  sdk: docker
  app_port: 7860
  pinned: false
  ---
  ```
- `.hfignore` to exclude unnecessary files
- This `Agent.md` file (must be committed before deployment)

---

## 2. API Exposure and Documentation

### Mandatory Endpoints
Every deployment **must** expose:

- **`/health`**
  - Returns HTTP 200 when the app is ready.
  - Required for Hugging Face to transition the Space from *starting* → *running*.

- **`/api-docs`**
  - Documents **all** available API endpoints.
  - Must be reachable at:
    `https://Leon4gr45-analytics.hf.space/api-docs`

### Functional Endpoints
Document each endpoint here. For every endpoint, include:

- **Method:** GET/POST/PUT/DELETE
- **Path:** `/predict`, `/generate`, `/upload`, etc.
- **Purpose:** What the endpoint does
- **Request Example:** JSON or query parameters
- **Response Example:** JSON schema or example payload

### /health
- Method: GET
- Purpose: Health check/Readiness test for transitioning space to running.
- Request: N/A
- Response:
  ```json
  {"ok": true}
  ```

### /api-docs
- Method: GET
- Purpose: Document all available API endpoints.
- Request: N/A
- Response:
  ```json
  {
    "endpoints": [...]
  }
  ```

### /api/event
- Method: POST
- Purpose: Send analytic events directly via API.
- Request:
  ```json
  {
    "name": "pageview",
    "url": "https://example.com"
  }
  ```
- Response:
  ```json
  {"ok": true}
  ```

All endpoints listed here appear in `/api-docs`.

---

## 3. Deployment Workflow

Precondition: Use the huggingface hub cli hf to check that the space is empty of files and delete any which are still in there and not belonging to the project to be uploaded.

### Standard Deployment Command
After any code change, run:

```bash
hf upload Leon4gr45/analytics --repo-type=space
```

### Scan build and run logs
Get build logs (SSE):
```bash
curl -N -H "Authorization: Bearer $HF_TOKEN" "https://huggingface.co/api/spaces/Leon4gr45/analytics/logs/build"
```

Get run logs (SSE) once the build logs succeed:
```bash
curl -N -H "Authorization: Bearer $HF_TOKEN" "https://huggingface.co/api/spaces/Leon4gr45/analytics/logs/run"
```

After 300 seconds, see if the deployment has been successful, and if not, fix the errors of deployment, and redeploy and monitor in a cycle until the space is running and reacts to the api endpoints you created.
