#!/bin/sh

# determine meil_host
if [ -z "${MEILI_HTTP_ADDR}" ]; then
    source .env
    meil_host=$SEARCH_DOMAIN
    echo "\n\nRunning locally"
else
    echo "\n\nRunning on Koyeb"
    meil_host="http://${MEILI_HTTP_ADDR}"

    # Wait until Meilisearch started and listens on port 7700.
    while [ -z "`netstat -tln | grep 7700`" ]; do
        echo '\n\nWaiting for Meilisearch to start ...'
        sleep 1
    done
    echo '\n\nMeilisearch started.'
fi

if [ -z "${PSQL_CONNECTION_STRING}" ]; then
    echo "\n\nEnvironment variable PSQL_CONNECTION_STRING is undefined."
    exit 1
fi

# generate sql file for dataset query
cat > $PWD/dataset.sql << EOF
\\t on
\\pset format unaligned
WITH result AS (
   $QUERY
)
SELECT json_agg(result) FROM result 
\g results.json
EOF

# run query and store json results
result=`psql $PSQL_CONNECTION_STRING -a -f $PWD/dataset.sql`

# simple wrapper function for api calls
function api_request() {
    action=$1

    case $action in
        "create")
            method="POST"
            endpoint="/indexes"
            payload='{"uid": "'$index'", "primaryKey": "id"}'
            ;;
        "settings")
            method="PATCH"
            endpoint="/indexes/${index}/settings"
            payload='{"searchableAttributes": ["*"], "filterableAttributes": ["company", "department", "locations", "days"], "sortableAttributes": ["days"], "pagination": {"maxTotalHits": 10000}}'
            ;;
        "add")
            method="POST"
            endpoint="/indexes/${index}/documents"
            payload="@results.json"
            ;;
        "swap")
            method="POST"
            endpoint="/swap-indexes"
            payload='[{"indexes": ["'$index'", "'$MEILI_INDEX'"]}]'
            ;;
        "delete")
            method="DELETE"
            endpoint="/indexes/${index}"
            payload=""
            ;;
        *)
            echo "Invalid action: $action"
            return 1
            ;;
    esac

    curl \
    -X $method "${meil_host}/${endpoint}" \
    -H "Authorization: Bearer ${MEILI_MASTER_KEY}" \
    -H "Content-Type: application/json" \
    --data-binary "${payload}"
}

## check to see if "./data.ms" directory exists
# if it doesn't get latest snapshot

if [ ! -d "./data.ms" ]; then
  echo "\n\nDirectory ./data.ms does not exist. Creating index..."
    # check to see if the directory exists, if not -- create new index
    index=$MEILI_INDEX

else
  echo "\n\nDirectory ./data.ms exists. Proceeding to re-index."
    if [ "$token" != "$WEBHOOK_AUTH" ]; then
        echo "Token is not valid."
        exit 1
    fi
    index="${MEILI_INDEX}New"
fi

# create new index 
echo "\n\nCreate new index for re-indexing...\n"
api_request "create"

# update settings of new index
echo "\n\nUpdate settings for new index...\n"
api_request "settings"

# add results to new index
echo "\n\nAdd documents to new index...\n"
api_request "add"

if [ "$index" != "$MEILI_INDEX" ]; then
    # swap indexes and remove unused index
    echo "\n\nPromote new index to production and remove old index...\n"
    api_request swap
    api_request delete
fi