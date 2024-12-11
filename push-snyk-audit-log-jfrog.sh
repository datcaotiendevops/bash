#!/bin/bash

set -eo pipefail

date=$(date -uI -d @$(($(date +%s) - 86400)))
startDate=$(date -u -d "$date 00:00:00" "+%Y-%m-%dT%H:%M:%SZ")
endDate=$(date -u -d "$date 23:59:59" "+%Y-%m-%dT%H:%M:%SZ")
truncate -s0 $date.json

[[ $ENV == prod ]] || echo running in dry run mode

# REST Api excluded api.access , thus calling twice
for eventsParam in "" "&events=api.access"; do
  nextPage="/rest/groups/$GROUP_ID/audit_logs/search?version=2024-11-28&size=100&from=$startDate&to=$endDate$eventsParam"
  while [[ "$nextPage" != "null" ]]; do
    url="https://api.snyk.io$nextPage"
    data=$(curl -sS --fail-with-body -H "Authorization: token $SNYK_TOKEN" $url)
    lines=$(echo $data | jq '.data.items | .[]' | wc -l)
    echo $data | jq '.data.items | .[]' | tee -a $date.json >/dev/null
    nextPage=$(echo $data | jq ".links.next" | sed 's/"//g')
    echo "calling api $eventsParam for $date , pulled $lines"
  done
done

# Overwrite the file with sorted content, the file save won't work if not using a tmp file
echo Total lines of data: $(wc -l $date.json)
cp $date.json tmp$date.json
jq -s 'sort_by(.created) | reverse | .[]' tmp$date.json > $date.json
rm tmp$date.json

echo pushing $date.json

[[ $ENV != prod ]] || curl -sS --fail-with-body -H "authorization: Bearer $ARTIFACTORY_TOKEN" -T $date.json \
  jfrog-path/$date.json
