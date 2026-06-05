#!/bin/bash

set -euo pipefail

MAXIMO_URL="${MAXIMO_URL:-}"
MAXIMO_USER="${MAXIMO_USER:-}"
MAXIMO_PASSWORD="${MAXIMO_PASSWORD:-}"
COUNT="${COUNT:-50}"
ORGID="${ORGID:-EAGLENA}"
SITEID="${SITEID:-BEDFORD}"
REPORTEDBY="${REPORTEDBY:-AIOPS}"
CLASSSTRUCTUREID="${CLASSSTRUCTUREID:-}"
DRY_RUN="${DRY_RUN:-false}"
CURL_INSECURE="${CURL_INSECURE:-false}"
MAXIMO_API_PATH="${MAXIMO_API_PATH:-/maximo/oslc/os/mxincident}"
RESPONSE_LOG="${RESPONSE_LOG:-false}"
MAXIMO_API_KEY="${MAXIMO_API_KEY:-}"
MAXIMO_COOKIE="${MAXIMO_COOKIE:-}"

if [ -z "$MAXIMO_URL" ] || [ -z "$MAXIMO_USER" ] || [ -z "$MAXIMO_PASSWORD" ]; then
  echo "Usage:"
  echo "  export MAXIMO_URL=https://your-maximo-instance.com"
  echo "  export MAXIMO_USER=youruser"
  echo "  export MAXIMO_PASSWORD=yourpassword"
  echo "  export ORGID=EAGLENA              # optional"
  echo "  export SITEID=BEDFORD             # optional"
  echo "  export REPORTEDBY=AIOPS           # optional"
  echo "  export CLASSSTRUCTUREID=1234      # optional"
  echo "  export COUNT=50                   # optional"
  echo "  export DRY_RUN=true               # optional, prints payloads only"
  echo "  export CURL_INSECURE=true         # optional, skip TLS verification"
  echo "  export MAXIMO_API_PATH=/maximo/oslc/os/mxincident   # optional"
  echo "  export RESPONSE_LOG=true          # optional, print API responses"
  echo "  echo 'If you still get HTTP 302, use an API key:'"
  echo "  export MAXIMO_API_KEY=yourapikey  # optional, preferred over password auth"
  echo "  export MAXIMO_COOKIE='LtpaToken2=...; JSESSIONID=...'  # optional, for SSO-protected Maximo"
  echo ""
  echo "Then run:"
  echo "  ./generate-maximo-incidents.sh"
  exit 1
fi

INCIDENT_TITLES=(
  "Database connection pool exhausted"
  "Application server CPU spike"
  "Memory leak detected in integration service"
  "User login failures increasing"
  "Disk usage exceeded threshold"
  "Network latency impacting transactions"
  "Email notification service unavailable"
  "Batch job processing delayed"
  "API gateway returning intermittent 502 errors"
  "SSL certificate nearing expiration"
)

INCIDENT_DETAILS=(
  "Multiple users reported slow response times and intermittent failures."
  "Monitoring detected sustained threshold breaches for more than 15 minutes."
  "Automated health checks are failing across one or more dependent services."
  "The issue appears to affect production workloads and requires investigation."
  "Recent deployment activity may correlate with the observed behavior."
  "Service degradation is visible in dashboards and alerting systems."
  "Operators observed retries, timeouts, and elevated error rates."
  "The incident may be related to infrastructure saturation or configuration drift."
  "Customer-facing functionality is partially impacted."
  "Immediate triage is recommended to prevent broader service disruption."
)

SEVERITIES=("1" "2" "3" "4")
STATUSES=("NEW" "QUEUED" "INPROG")

build_payload() {
  local index="$1"
  local title_index=$((RANDOM % ${#INCIDENT_TITLES[@]}))
  local detail_index=$((RANDOM % ${#INCIDENT_DETAILS[@]}))
  local severity_index=$((RANDOM % ${#SEVERITIES[@]}))
  local status_index=$((RANDOM % ${#STATUSES[@]}))
  local source_id
  source_id=$(printf "AIOPS-%04d" "$index")

  local description="${INCIDENT_TITLES[$title_index]} [$source_id]"
  local long_description="${INCIDENT_DETAILS[$detail_index]} Source reference: $source_id."

  cat <<EOF
{
  "description": "$description",
  "description_longdescription": "$long_description",
  "reportedby": "$REPORTEDBY",
  "orgid": "$ORGID",
  "siteid": "$SITEID",
  "status": "${STATUSES[$status_index]}",
  "internalpriority": ${SEVERITIES[$severity_index]},
  "reportedpriority": ${SEVERITIES[$severity_index]}$(if [ -n "$CLASSSTRUCTUREID" ]; then printf ',\n  "classstructureid": "%s"' "$CLASSSTRUCTUREID"; fi)
}
EOF
}

echo "Creating $COUNT fake Maximo incidents against $MAXIMO_URL$MAXIMO_API_PATH"

CURL_TLS_ARGS=()
if [ "$CURL_INSECURE" = "true" ]; then
  CURL_TLS_ARGS=(-k)
fi

for i in $(seq 1 "$COUNT"); do
  payload="$(build_payload "$i")"

  if [ "$DRY_RUN" = "true" ]; then
    echo "----- Incident $i -----"
    echo "$payload"
    echo ""
    continue
  fi

  echo "[$i/$COUNT] Creating incident..."
  CURL_AUTH_ARGS=()
  if [ -n "$MAXIMO_COOKIE" ]; then
    CURL_AUTH_ARGS=(-H "Cookie: $MAXIMO_COOKIE")
  elif [ -n "$MAXIMO_API_KEY" ]; then
    CURL_AUTH_ARGS=(-H "apikey: $MAXIMO_API_KEY")
  else
    CURL_AUTH_ARGS=(-u "$MAXIMO_USER:$MAXIMO_PASSWORD" -H "maxauth: $(printf '%s:%s' "$MAXIMO_USER" "$MAXIMO_PASSWORD" | base64)")
  fi

  response=$(curl --silent --show-error "${CURL_TLS_ARGS[@]}" "${CURL_AUTH_ARGS[@]}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -X POST \
    -w $'\nHTTP_STATUS:%{http_code}' \
    "$MAXIMO_URL$MAXIMO_API_PATH?lean=1&_format=json" \
    -d "$payload")
  http_status="${response##*HTTP_STATUS:}"
  response_body="${response%$'\n'HTTP_STATUS:*}"

  if [ "$http_status" -lt 200 ] || [ "$http_status" -ge 300 ]; then
    echo "Request failed with HTTP $http_status"
    echo "$response_body"
    exit 1
  fi

  if [ "$RESPONSE_LOG" = "true" ]; then
    echo "$response_body"
  fi
done

if [ "$DRY_RUN" != "true" ]; then
  echo "Done. Created $COUNT incidents."
  echo "Verify with: $MAXIMO_URL$MAXIMO_API_PATH?oslc.select=ticketid,description,status&oslc.pageSize=10&_format=json"
fi

# Made with Bob
