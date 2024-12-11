#!/bin/bash

set -eo pipefail

date=$(date -uI -d @$(($(date +%s) - 86400))) // calculate date before one day
startDate=$(date -u -d "$date 00:00:00" "+%Y-%m-%dT%H:%M:%SZ") // get 00:00:00 day from above
endDate=$(date -u -d "$date 23:59:59" "+%Y-%m-%dT%H:%M:%SZ")
truncate -s0 $date.json

[[ $ENV == prod ]] || echo running in dry run mode

# REST Api excluded api.access , thus calling twice
for eventsParam in "" "&events=api.access"; do
  nextPage="/rest/groups/$GROUP_ID/audit_logs/search?version=2024-11-28&size=100&from=$startDate&to=$endDate$eventsParam"
  while [[ "$nextPage" != "null" ]]; do
    url="https://api.snyk.io$nextPage"
    data=$(curl -sS --fail-with-body -H "Authorization: token $SNYK_TOKEN" $url)
    lines=$(echo $data | jq '.data.items | .[]' | wc -l) // get each item in json data.items and part it like each json object and count how many line of object
    echo $data | jq '.data.items | .[]' | tee -a $date.json >/dev/null // write data.items to date.json and output to dev/null
    nextPage=$(echo $data | jq ".links.next" | sed 's/"//g') // remove "" in next url
    echo "calling api $eventsParam for $date , pulled $lines"
  done
done

# Overwrite the file with sorted content, the file save won't work if not using a tmp file
echo Total lines of data: $(wc -l $date.json)
cp $date.json tmp$date.json
jq -s 'sort_by(.created) | reverse | .[]' tmp$date.json > $date.json // jq -s to make json array, sort by create and make it oder by created 
rm tmp$date.json

echo pushing $date.json

[[ $ENV != prod ]] || curl -sS --fail-with-body -H "authorization: Bearer $ARTIFACTORY_TOKEN" -T $date.json \
  jfrog-path/$date.json
