#!/bin/sh

if [ -z "${MEILI_HTTP_ADDR}" ]; then
  echo "Environment variable MEILI_HTTP_ADDR is undefined."
  exit 1
fi

if [ -z "${MEILI_MASTER_KEY}" ]; then
  echo "Environment variable MEILI_MASTER_KEY is undefined."
  exit 1
fi

if [ -z "${PSQL_CONNECTION_STRING}" ]; then
  echo "Environment variable PSQL_CONNECTION_STRING is undefined."
  exit 1
fi

# start meilisearch
/usr/bin/supervisord -c /etc/supervisord.conf