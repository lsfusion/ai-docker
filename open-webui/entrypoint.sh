#!/bin/bash
set -e

DB_FILE="/app/backend/data/webui.db"
START_SCRIPT="/app/backend/start.sh"

MCP_ID="${MCP_ID:-default_id}"
MCP_NAME="${MCP_NAME:-Default MCP}"
MCP_URL="${MCP_URL:-http://localhost}"
MCP_PATH="${MCP_PATH:-openapi.json}"

mkdir -p /app/backend/data

echo "Initializing OpenWebUI configuration..."

NEED_INIT=0
if [ ! -f "$DB_FILE" ]; then
    echo "Database file not found, will initialize schema."
    NEED_INIT=1
else
    echo "Database file exists, checking schema..."
    if ! sqlite3 "$DB_FILE" "SELECT name FROM sqlite_master WHERE type='table' AND name='config';" | grep -q "config"; then
        echo "Config table missing — need initialization."
        NEED_INIT=1
    fi
fi

if [ "$NEED_INIT" -eq 1 ]; then
    echo "Running OpenWebUI once to auto-create schema..."

    bash "$START_SCRIPT" &
    PID=$!

    echo "Waiting for database creation..."
    while [ ! -f "$DB_FILE" ]; do
        sleep 1
    done

    # waiting for config table
    until sqlite3 "$DB_FILE" "SELECT name FROM sqlite_master WHERE type='table' AND name='config';" | grep -q "config"; do
        sleep 1
    done

    echo "Schema ready. Killing bootstrap instance..."
    kill $PID || true
    sleep 2
else
    echo "Database schema already initialized. Skipping bootstrap."
fi

echo "Updating config table..."

python3 <<EOF
import sqlite3, json

db = "${DB_FILE}"

conn = sqlite3.connect(db)
cur = conn.cursor()

cur.execute("SELECT id, data FROM config LIMIT 1;")
row = cur.fetchone()

if row is None:
    base = {"version": 0, "ui": {}, "tool_server": {"connections": []}}
    cur.execute("INSERT INTO config (id, data, version) VALUES (1, ?, 0)", (json.dumps(base),))
    conn.commit()
    cur.execute("SELECT id, data FROM config LIMIT 1;")
    row = cur.fetchone()

config_id, data_json = row
data = json.loads(data_json)

tool_server = data.setdefault("tool_server", {})
connections = tool_server.setdefault("connections", [])

mcp_id   = "${MCP_ID}"
mcp_name = "${MCP_NAME}"
mcp_url  = "${MCP_URL}"
mcp_path = "${MCP_PATH}"

found = next((c for c in connections if c.get("url") == mcp_url), None)

new_item = {
    "url": mcp_url,
    "path": mcp_path,
    "type": "mcp",
    "auth_type": "none",
    "key": "",
    "config": {
        "enable": True,
        "access_control": {
            "read": {"group_ids": [], "user_ids": []},
            "write": {"group_ids": [], "user_ids": []}
        }
    },
    "spec_type": "url",
    "spec": "",
    "info": {
        "id": mcp_id,
        "name": mcp_name,
        "description": ""
    }
}

if found:
    found.update(new_item)
else:
    connections.append(new_item)

cur.execute("UPDATE config SET data = ? WHERE id = ?;", (json.dumps(data), config_id))
conn.commit()
conn.close()
EOF

echo "Config update complete."

echo "Starting OpenWebUI..."
exec bash "$START_SCRIPT"
