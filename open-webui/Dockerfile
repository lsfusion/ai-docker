FROM ghcr.io/open-webui/open-webui:latest

RUN apt update && apt install -y sqlite3

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]