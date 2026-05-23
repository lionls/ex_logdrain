# ExLogdrain

A [Vercel Log Drain](https://vercel.com/docs/observability/log-drains) endpoint that ingests, verifies, and persists logs to S3 as incremental Parquet files via [DuckDB](https://duckdb.org/).

## Architecture

```
POST /vercel  →  Verify HMAC-SHA1  →  LogBuffer (in-memory)  →  DuckDB (local, ephemeral)
                                                                  │
                                                    every 15 min  │  COPY + DELETE
                                                                  ▼
                                                    s3://bucket/logs/date=YYYY-MM-DD/
                                                      HH-MM_xxxx.parquet
```

- Logs are buffered in memory and flushed to a local DuckDB every `LOG_FLUSH_INTERVAL` seconds.
- Every 15 minutes, a snapshot exports all buffered rows as a new Parquet file on S3 and clears the local table.
- Each file contains only the rows from that 15-minute window — no rewrites, no compaction needed.
- The local DuckDB file lives at `storage/logs.duckdb` and serves purely as a write buffer.

## Quick Start

```bash
# Set required env vars
export VERCEL_WEBHOOK_SECRET="your-secret-from-vercel"
export S3_BUCKET="my-log-bucket"
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="..."

# Install and run
mix deps.get
iex -S mix
```

Then configure your Vercel Log Drain to point at `https://your-domain/vercel` with the same webhook secret.

## Configuration

| Env var | Required | Default | Description |
|---|---|---|---|
| `VERCEL_WEBHOOK_SECRET` | production | — | Shared secret for HMAC-SHA1 signature verification |
| `LOG_FLUSH_INTERVAL` | no | `5` | Seconds between buffer flushes to local DuckDB |
| `PORT` | no | `4000` | HTTP listen port |
| `S3_BUCKET` | for S3 | — | S3 bucket for Parquet snapshots (omit for local disk) |
| `S3_REGION` | no | `us-east-1` | S3 region |
| `AWS_ACCESS_KEY_ID` | for S3 | — | AWS access key |
| `AWS_SECRET_ACCESS_KEY` | for S3 | — | AWS secret key |
| `S3_ENDPOINT` | no | — | Custom S3-compatible endpoint (MinIO, etc.) |

## Vercel Drain Verification

When you add the drain in Vercel, it sends a `POST` with an `x-vercel-verify` header containing a token. The endpoint echoes the token back to confirm it's reachable. After verification, all log deliveries are signed with `x-vercel-signature` (HMAC-SHA1 of the raw body).

## Querying Logs

From DuckDB or any Parquet-compatible tool:

```sql
-- Today's logs
SELECT * FROM read_parquet('s3://my-log-bucket/logs/date=2026-05-23/*.parquet');

-- Full date range
SELECT * FROM read_parquet('s3://my-log-bucket/logs/**/*.parquet')
WHERE epoch_ms(timestamp) BETWEEN 1700000000000 AND 1700086400000;

-- Most recent errors
SELECT * FROM read_parquet('s3://my-log-bucket/logs/**/*.parquet')
WHERE level = 'error'
ORDER BY timestamp DESC
LIMIT 50;
```

## Retention

Set an S3 lifecycle rule on the `logs/` prefix to expire objects older than your desired retention period. The local `storage/logs.duckdb` only holds data between snapshot intervals.

## Schema

Each Parquet file has 30 columns matching the Vercel log drain payload:

| Column | Type | Source |
|---|---|---|
| `id` | VARCHAR | `log.id` |
| `deployment_id` | VARCHAR | `log.deploymentId` |
| `source` | VARCHAR | `log.source` |
| `host` | VARCHAR | `log.host` |
| `timestamp` | BIGINT | `log.timestamp` (unix ms) |
| `project_id` | VARCHAR | `log.projectId` |
| `level` | VARCHAR | `log.level` |
| `message` | VARCHAR | `log.message` |
| `project_name` | VARCHAR | `log.projectName` |
| `build_id` | VARCHAR | `log.buildId` |
| `type` | VARCHAR | `log.type` |
| `entrypoint` | VARCHAR | `log.entrypoint` |
| `request_id` | VARCHAR | `log.requestId` |
| `status_code` | INTEGER | `log.statusCode` |
| `path` | VARCHAR | `log.path` |
| `execution_region` | VARCHAR | `log.executionRegion` |
| `environment` | VARCHAR | `log.environment` |
| `trace_id` | VARCHAR | `log.traceId` or `log.trace.id` |
| `span_id` | VARCHAR | `log.spanId` or `log.span.id` |
| `proxy_*` | various | Flattened `log.proxy.*` fields |

## Tests

```bash
mix test
```
