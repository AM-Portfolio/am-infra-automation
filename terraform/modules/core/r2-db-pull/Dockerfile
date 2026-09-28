# DR pull worker: download R2 prod/latest + restore PG/Mongo (same toolkit as dump image)
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl gzip python3 gnupg \
      redis-tools \
    && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
      | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" \
      > /etc/apt/sources.list.d/pgdg.list \
    && curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc \
      | gpg --dearmor -o /usr/share/keyrings/mongodb.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/mongodb.gpg] https://repo.mongodb.org/apt/debian bookworm/mongodb-org/7.0 main" \
      > /etc/apt/sources.list.d/mongodb-org-7.0.list \
    && apt-get update && apt-get install -y --no-install-recommends \
      postgresql-client-16 \
      mongodb-database-tools \
    && rm -rf /var/lib/apt/lists/*

COPY pull.sh /usr/local/bin/am-r2-db-pull
RUN chmod +x /usr/local/bin/am-r2-db-pull \
    && sed -i 's/\r$//' /usr/local/bin/am-r2-db-pull

ENTRYPOINT ["/usr/local/bin/am-r2-db-pull"]
