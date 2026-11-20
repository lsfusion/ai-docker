# mcp-data — what the `mcp` service keeps on the host

Two bind mounts of the `mcp` service in `../docker-compose.yml`. Their contents
stay out of git (see `.gitignore`).

## `logs/` → `/data/logs` (`LOG_DIR`)

- `retrieval-YYYYMMDD.jsonl` — one line per `lsfusion_retrieve_docs` call (analytics).
- `reports/inbox/` — every `lsfusion_report_feedback` report as its own JSON file
  (`REPORTS_DIR` defaults to `<LOG_DIR>/reports`). The Jenkins job
  `postFeedbackIssues` posts each one as an issue in `lsfusion/platform-feedback`
  and moves the file to `reports/processed/`.
- `reports-YYYYMMDD.jsonl` — a short event journal without report text: one
  `report_stored` line per stored report (id, `signal_type`, `payload_size`) and
  one `report_feedback` line with `ok: false` per refused report.

Writing is best-effort: a failure never breaks a tool, it only prints an
`event_log_error` line to the container's stderr. Check after a deploy:
`docker logs stack-mcp-1 2>&1 | grep event_log_error`.

## `snapshot/` → `/data/snapshot` (`RAG_SNAPSHOT_PATH`)

`corpus.npz` is the only index `lsfusion_retrieve_docs` searches; without it the
tool answers with an error. The Jenkins job `ragBuildSnapshot` rebuilds it after
docs commits on platform master and replaces it atomically (temp file + `mv`).
If a rebuild fails, the old snapshot stays, and the server logs a warning on
load once it is older than `SNAPSHOT_MAX_AGE_DAYS` (7).

## Ownership

The container runs as non-root **uid 10001**, so it must own the directories:

```bash
mkdir -p /opt/stack/mcp-data/logs /opt/stack/mcp-data/snapshot
chown -R 10001:10001 /opt/stack/mcp-data
```

## Settings that live only on the host

Not in git (names only):

- `/etc/environment`: `OPENAI_API_KEY`, `PINECONE_API_KEY`, `MODEL_ID`, `DOMAIN`,
  `MCP_PATH`, `OPENAI_PATH`, `LETSENCRYPT_EMAIL`;
- `/opt/stack/.env`: `RAG_VECTOR_STORE_ID`, `RETRIEVAL_BACKEND`.

The compose file still passes `RETRIEVAL_BACKEND`, `RAG_VECTOR_STORE_ID` and
`PINECONE_API_KEY`, but the server no longer reads them: it has no vector-store
fallback, so setting `RETRIEVAL_BACKEND=store` changes nothing.

## Changing the stack

This repository is the source of truth for `/opt/stack`; do not edit the files
on the box. A change goes:

1. commit and push here;
2. on the box: `cd /opt/stack && git pull --ff-only`;
3. `docker compose up -d <service>` for the changed service only.

`caddy/Caddyfile` is bind-mounted on its own: `git pull` replaces it with a new
file, and the running container keeps seeing the old one, so `caddy reload` does
not pick the change up. Validate, then recreate (HTTPS, `/mcp` included, is down
for a few seconds):

```bash
docker compose run --rm --no-deps caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
docker compose up -d --force-recreate caddy
```

The `deployMcp` Jenkins job only refreshes the `mcp` image
(`docker compose pull mcp && docker compose up -d mcp`); it never runs
`git pull`, so compose changes reach the box only as above.

## Log retention (proposal, not installed)

The dated JSONL files are not rotated by Docker's `json-file` driver (that caps
only the container's stdout/stderr). A host cron could prune them by age —
retrieval is high volume / low value, the report journal is kept longer:

```cron
# /etc/cron.d/mcp-log-retention  (UTC)
17 4 * * * root find /opt/stack/mcp-data/logs -name 'retrieval-*.jsonl' -mtime +90  -delete
23 4 * * * root find /opt/stack/mcp-data/logs -name 'reports-*.jsonl'   -mtime +365 -delete
```

Check the disk budget of the single VM before settling the windows.
