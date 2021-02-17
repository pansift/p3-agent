#!/usr/bin/env bash

# Require an UUID argument or just exit.

if [[ $1 =~ ^\{?[A-F0-9a-f]{8}-[A-F0-9a-f]{4}-[A-F0-9a-f]{4}-[A-F0-9a-f]{4}-[A-F0-9a-f]{12}\}?$ ]]; then
  url="http://webrouter.infra.p3.pansift.com:443/hooks/setup"
  token=$(curl -s --data "uuid=$1" $url | cut -d',' -f3 | tr -d '\r')
  [[ "${#token}" -eq 88 ]] && export pansift_token=$token && echo "$token" || echo "null"
else
  exit 0
fi
