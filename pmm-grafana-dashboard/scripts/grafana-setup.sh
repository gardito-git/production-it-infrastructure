#!/bin/bash
# One-time Grafana setup through its API:
#   1. a service account + token for pmm-agent registration, published to
#      Secrets Manager for every server to pick up
#   2. Loki and Kubernetes Prometheus data sources
#   3. Kubernetes dashboards from grafana.com
source /opt/monitoring-bootstrap/lib.sh

PMM_ADMIN_PASSWORD=$(admin_password)

# --- 1. Agent token -------------------------------------------------------------
if [[ -n $(secret_field "$AGENT_TOKEN_SECRET_ARN" token) ]]; then
  log "Agent token already published"
else
  log "Creating the pmm-agents service account and its token"
  SA_ID=$(grafana GET "/serviceaccounts/search?query=pmm-agents" | jq -r '.serviceAccounts[] | select(.name == "pmm-agents") | .id' | head -n 1)
  if [[ -z $SA_ID ]]; then
    SA_ID=$(grafana POST /serviceaccounts '{"name":"pmm-agents","role":"Admin"}' | jq -r .id)
  fi
  [[ $SA_ID =~ ^[0-9]+$ ]] || die "could not create the pmm-agents service account"
  TOKEN=$(grafana POST "/serviceaccounts/$SA_ID/tokens" "{\"name\":\"agents-$(date -u +%Y%m%d%H%M%S)\"}" | jq -r .key)
  [[ $TOKEN == glsa_* ]] || die "could not create a service account token"
  # Through stdin, so the token isn't on a command line.
  jq -n --arg t "$TOKEN" '{token: $t}' |
    aws secretsmanager put-secret-value --secret-id "$AGENT_TOKEN_SECRET_ARN" --secret-string file:///dev/stdin >/dev/null
  log "Agent token published; servers register within 5 minutes"
fi

# --- 2. Data sources ----------------------------------------------------------
add_datasource() {
  local name=$1 type=$2 url=$3 uid=$4
  if grafana GET "/datasources/uid/$uid" >/dev/null 2>&1; then
    log "Data source $name already exists"
  else
    grafana POST /datasources "{\"name\":\"$name\",\"type\":\"$type\",\"url\":\"$url\",\"access\":\"proxy\",\"uid\":\"$uid\"}" >/dev/null
    log "Added data source $name"
  fi
}
add_datasource "Loki" loki http://loki:3100 loki
add_datasource "Kubernetes" prometheus http://prometheus:9090 kubernetes-prometheus

# --- 3. Kubernetes dashboards ---------------------------------------------------
# Community dashboards (github.com/dotdc/grafana-dashboards-kubernetes):
# cluster overview, namespaces, nodes, pods. Best effort: a failed download
# doesn't stop the bootstrap; import them later from the UI by ID.
FOLDER_UID=kubernetes
grafana GET "/folders/$FOLDER_UID" >/dev/null 2>&1 ||
  grafana POST /folders "{\"uid\":\"$FOLDER_UID\",\"title\":\"Kubernetes\"}" >/dev/null || true

for id in 15757 15758 15759 15760; do
  if json=$(curl -fsSL --retry 3 "https://grafana.com/api/dashboards/$id/revisions/latest/download"); then
    payload=$(DASHBOARD_JSON="$json" python3 - "$FOLDER_UID" <<'PY'
import json, os, sys
dashboard = json.loads(os.environ["DASHBOARD_JSON"])
inputs = [
    {"name": i["name"], "type": "datasource", "pluginId": "prometheus", "value": "kubernetes-prometheus"}
    for i in dashboard.get("__inputs", [])
    if i.get("type") == "datasource" and i.get("pluginId") == "prometheus"
]
dashboard.pop("id", None)
print(json.dumps({"dashboard": dashboard, "overwrite": True, "inputs": inputs, "folderUid": sys.argv[1]}))
PY
    )
    if grafana POST /dashboards/import "$payload" >/dev/null; then
      log "Imported Kubernetes dashboard $id"
    else
      log "WARNING: could not import dashboard $id"
    fi
  else
    log "WARNING: could not download dashboard $id from grafana.com"
  fi
done

log "Grafana setup finished"
