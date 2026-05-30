# mcp-data — MCP feedback-loop log sink (Phase A2)

The `mcp` service bind-mounts `./mcp-data/logs` → `/data/logs` (env `LOG_DIR=/data/logs`).
The MCP server appends dated JSONL there:

- `retrieval-YYYYMMDD.jsonl` — one line per `lsfusion_retrieve_docs` call (analytics).
- `reports-YYYYMMDD.jsonl` — one line per `lsfusion_report_feedback` submission.

Writing is **best-effort**: a failure never breaks the tools — it only emits a JSON
`event_log_error` line to stderr. So a permissions/mount problem is SILENT except in
the container's stderr. Monitor it after deploy:
`docker logs stack-mcp-1 2>&1 | grep event_log_error`.

The `logs/` contents are kept OUT of git (see `.gitignore`); only `.gitkeep` is tracked.

## Deploy (host: ai.lsfusion.org, /opt/stack)

The container runs as non-root **uid 10001**, so the host dir MUST be writable by it:

```bash
mkdir -p /opt/stack/mcp-data/logs
chown -R 10001:10001 /opt/stack/mcp-data
```

The `deployMcp` Jenkins job does `docker compose pull && up -d mcp` — it does NOT
`git pull`. And `/opt/stack/docker-compose.yml` has drifted from github HEAD
(box keeps `RAG_VECTOR_STORE_ID` and comments out `openwebui`). So do NOT blindly
`git pull` github HEAD onto the box. Apply ONLY the `mcp`-service deltas
(`RAG_VECTOR_STORE_ID`, `LOG_DIR`, the `volumes` bind-mount, the `logging` cap) to the
deployed file, then recreate only mcp:

```bash
docker compose pull mcp && docker compose up -d --no-deps --force-recreate mcp
```

## Retention

The dated JSONL files are NOT rotated by Docker's `json-file` driver (that caps only
the container's stdout/stderr). Add a host cron to prune by age — retrieval is high
volume / low value, reports are kept longer:

```cron
# /etc/cron.d/mcp-log-retention  (UTC)
17 4 * * * root find /opt/stack/mcp-data/logs -name 'retrieval-*.jsonl' -mtime +90  -delete
23 4 * * * root find /opt/stack/mcp-data/logs -name 'reports-*.jsonl'   -mtime +365 -delete
```

Check disk budget on the single VM before raising these windows.
