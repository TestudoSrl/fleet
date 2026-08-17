#!/usr/bin/env bash
set -euo pipefail

: "${CF_API_TOKEN:?CF_API_TOKEN is required}"
: "${CF_ZONE_ID:?CF_ZONE_ID is required}"

host="${1:?usage: upsert-dns.sh <fqdn> <ipv4>}"
ipv4="${2:?usage: upsert-dns.sh <fqdn> <ipv4>}"
api="https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records"
auth=(-H "Authorization: Bearer ${CF_API_TOKEN}" -H "Content-Type: application/json")

lookup="$(curl -fsS --get "${auth[@]}" --data-urlencode "name=${host}" "${api}")"
count="$(jq -r '.result | length' <<<"${lookup}")"
if [ "${count}" -gt 1 ]; then
  echo "Refusing to modify ${host}: ${count} records already exist" >&2
  exit 1
fi

payload="$(jq -n --arg name "${host}" --arg content "${ipv4}" \
  '{type:"A",name:$name,content:$content,proxied:true,ttl:1}')"

if [ "${count}" -eq 1 ]; then
  record_id="$(jq -r '.result[0].id' <<<"${lookup}")"
  response="$(curl -fsS -X PUT "${auth[@]}" "${api}/${record_id}" -d "${payload}")"
  action="Updated"
else
  response="$(curl -fsS -X POST "${auth[@]}" "${api}" -d "${payload}")"
  action="Created"
fi

jq -e '.success == true and .result.proxied == true and .result.type == "A"' \
  >/dev/null <<<"${response}"
echo "${action} proxied A record ${host} -> ${ipv4}"

