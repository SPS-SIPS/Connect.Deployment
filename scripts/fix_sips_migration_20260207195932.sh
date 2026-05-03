#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Fix SIPS EF migration 20260207195932_AddMsgIdUniqueConstraint manually.

This script removes duplicate isomessages by keeping the newest id for each:
  - (messagetype, msgid)
  - (messagetype, txid)

It then creates the unique indexes and records the EF migration as applied.

Required environment variables:
  DB_HOST       PostgreSQL host or IP address
  DB_NAME       PostgreSQL database name
  DB_USER       PostgreSQL username
  DB_PASSWORD   PostgreSQL password

Optional environment variables:
  DB_PORT       PostgreSQL port. Defaults to 5432
  LOCK_TIMEOUT  Lock wait for cleanup/index commands. Defaults to 0 (wait forever)

Usage:
  # Preview only, no data changes:
  DB_HOST=10.0.0.10 DB_NAME='SIPS.Connect.DB' DB_USER=postgres DB_PASSWORD='secret' \
    ./scripts/fix_sips_migration_20260207195932.sh

  # Apply cleanup and migration marker:
  DB_HOST=10.0.0.10 DB_NAME='SIPS.Connect.DB' DB_USER=postgres DB_PASSWORD='secret' \
    ./scripts/fix_sips_migration_20260207195932.sh --apply

Recommended before --apply:
  docker compose stop sips-connect
USAGE
}

APPLY=false
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
elif [[ "${1:-}" == "--apply" ]]; then
  APPLY=true
elif [[ $# -gt 0 ]]; then
  echo "Unknown argument: $1" >&2
  usage >&2
  exit 2
fi

: "${DB_HOST:?set DB_HOST}"
: "${DB_PORT:=5432}"
: "${LOCK_TIMEOUT:=0}"
: "${DB_NAME:?set DB_NAME}"
: "${DB_USER:?set DB_USER}"
: "${DB_PASSWORD:?set DB_PASSWORD}"

export PGPASSWORD="$DB_PASSWORD"

PSQL=(
  psql
  --host="$DB_HOST"
  --port="$DB_PORT"
  --username="$DB_USER"
  --dbname="$DB_NAME"
  --set=ON_ERROR_STOP=1
)

echo "Target database:"
echo "  Host: $DB_HOST"
echo "  Port: $DB_PORT"
echo "  Database: $DB_NAME"
echo "  Username: $DB_USER"
echo "  Lock timeout: $LOCK_TIMEOUT"
echo

echo "Equivalent .NET connection string:"
echo "  Host=$DB_HOST;Port=$DB_PORT;Database=$DB_NAME;Username=$DB_USER;Password=***;Include Error Detail=True;"
echo

echo "Running duplicate preview..."
"${PSQL[@]}" --set=lock_timeout="$LOCK_TIMEOUT" <<'SQL'
\echo 'Duplicate summary'

SELECT 'msgid duplicate groups' AS check, COUNT(*) AS groups
FROM (
  SELECT messagetype, msgid
  FROM isomessages
  WHERE msgid IS NOT NULL AND msgid <> ''
  GROUP BY messagetype, msgid
  HAVING COUNT(*) > 1
) x;

SELECT 'txid duplicate groups' AS check, COUNT(*) AS groups
FROM (
  SELECT messagetype, txid
  FROM isomessages
  WHERE txid IS NOT NULL AND txid <> ''
  GROUP BY messagetype, txid
  HAVING COUNT(*) > 1
) x;

WITH duplicate_iso_ids AS (
  SELECT id
  FROM (
    SELECT
      id,
      ROW_NUMBER() OVER (
        PARTITION BY messagetype, msgid
        ORDER BY id DESC
      ) AS rn
    FROM isomessages
    WHERE msgid IS NOT NULL AND msgid <> ''
  ) d
  WHERE rn > 1

  UNION

  SELECT id
  FROM (
    SELECT
      id,
      ROW_NUMBER() OVER (
        PARTITION BY messagetype, txid
        ORDER BY id DESC
      ) AS rn
    FROM isomessages
    WHERE txid IS NOT NULL AND txid <> ''
  ) d
  WHERE rn > 1
)
SELECT COUNT(*) AS duplicate_isomessages_to_delete
FROM duplicate_iso_ids;
SQL

if [[ "$APPLY" != "true" ]]; then
  echo
  echo "Preview complete. No changes were made."
  echo "Re-run with --apply after stopping sips-connect."
  exit 0
fi

echo
echo "Applying cleanup. Make sure sips-connect is stopped."
read -r -p "Type APPLY to continue: " confirmation
if [[ "$confirmation" != "APPLY" ]]; then
  echo "Aborted."
  exit 1
fi

"${PSQL[@]}" --set=lock_timeout="$LOCK_TIMEOUT" <<'SQL'
\echo 'Cleaning duplicate ISO messages'

BEGIN;

SET LOCAL statement_timeout = 0;
SET LOCAL lock_timeout = :'lock_timeout';

CREATE TEMP TABLE duplicate_iso_ids (
  id integer PRIMARY KEY
) ON COMMIT DROP;

INSERT INTO duplicate_iso_ids (id)
SELECT id
FROM (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY messagetype, msgid
      ORDER BY id DESC
    ) AS rn
  FROM isomessages
  WHERE msgid IS NOT NULL AND msgid <> ''
) d
WHERE rn > 1
ON CONFLICT DO NOTHING;

INSERT INTO duplicate_iso_ids (id)
SELECT id
FROM (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY messagetype, txid
      ORDER BY id DESC
    ) AS rn
  FROM isomessages
  WHERE txid IS NOT NULL AND txid <> ''
    AND id NOT IN (SELECT id FROM duplicate_iso_ids)
) d
WHERE rn > 1
ON CONFLICT DO NOTHING;

SELECT COUNT(*) AS duplicate_isomessages_to_delete
FROM duplicate_iso_ids;

DELETE FROM transactions
WHERE isomessageid IN (SELECT id FROM duplicate_iso_ids);

DELETE FROM isomessagestatuses
WHERE isomessageid IN (SELECT id FROM duplicate_iso_ids);

DELETE FROM isomessages
WHERE id IN (SELECT id FROM duplicate_iso_ids);

COMMIT;
SQL

"${PSQL[@]}" --set=lock_timeout="$LOCK_TIMEOUT" <<'SQL'
\echo 'Creating unique indexes concurrently'

SET statement_timeout = 0;
SET lock_timeout = :'lock_timeout';

DROP INDEX CONCURRENTLY IF EXISTS ux_iso_msg_type_msgid;
CREATE UNIQUE INDEX CONCURRENTLY ux_iso_msg_type_msgid
ON isomessages (messagetype, msgid)
WHERE "msgid" IS NOT NULL AND "msgid" <> '';

DROP INDEX CONCURRENTLY IF EXISTS ux_iso_msg_type_txid;
CREATE UNIQUE INDEX CONCURRENTLY ux_iso_msg_type_txid
ON isomessages (messagetype, txid)
WHERE "txid" IS NOT NULL AND "txid" <> '';

\echo 'Recording EF migration history'

BEGIN;

INSERT INTO "__EFMigrationsHistory" (migrationid, productversion)
VALUES ('20260207195932_AddMsgIdUniqueConstraint', '9.0.1')
ON CONFLICT (migrationid) DO NOTHING;

COMMIT;

\echo 'Done.'
SQL

echo
echo "Migration cleanup complete. You can now start sips-connect:"
echo "  docker compose up -d sips-connect"
