#!/bin/sh

# determine meil_host
if [ -z "${MEILI_HTTP_ADDR}" ]; then
    source .env
    meil_host=$SEARCH_DOMAIN
    echo "Running locally"
else
    echo "Running on Koyeb"
    meil_host="http://${MEILI_HTTP_ADDR}"

    # Wait until Meilisearch started and listens on port 7700.
    while [ -z "`netstat -tln | grep 7700`" ]; do
        echo 'Waiting for Meilisearch to start ...'
        sleep 1
    done
    echo 'Meilisearch started.'
fi

if [ -z "${PSQL_CONNECTION_STRING}" ]; then
    echo "Environment variable PSQL_CONNECTION_STRING is undefined."
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

# the below line should check to see if any files exist in the directory ./data.ms/indexes
if [ -z "$(ls -A ./data.ms/indexes)" ]; then
  echo "Index in ./data.ms/indexes does not exist. Creating index..."
    # check to see if the directory exists, if not -- create new index
    index=$MEILI_INDEX

else
  echo "Index in ./data.ms/indexes exist. Proceeding to re-index."
    if [ "$token" != "$WEBHOOK_AUTH" ]; then
        echo "Token is not valid."
        exit 1
    fi
    index="${MEILI_INDEX}New"
fi

# create new index 
echo "Create new index for re-indexing..."
api_request "create"

# update settings of new index
echo "Update settings for new index..."
api_request "settings"

# add results to new index
echo "Add documents to new index..."
api_request "add"

if [ "$index" != "$MEILI_INDEX" ]; then
    # swap indexes and remove unused index
    echo "Promote new index to production and remove old index..."
    api_request swap
    api_request delete
fi