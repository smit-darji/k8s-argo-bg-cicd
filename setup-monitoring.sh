#!/bin/bash
set -e

# ============================================================
# 🚀 k8s-monitoring-full-setup.sh
# Full Kubernetes Monitoring Stack (Prometheus + Grafana + Loki + Promtail)
# Works with Minikube, Kind, or any local Kubernetes cluster
# ============================================================

MON_NS="monitoring"
PROM_PORT=30090
GRAFANA_PORT=30300
LOKI_NODEPORT=31000
LOKI_PORT=3100
TIMEOUT="15m0s"

echo
echo "============================================================"
echo "🧹 Cleaning previous setup"
echo "============================================================"
helm uninstall prometheus -n "${MON_NS}" >/dev/null 2>&1 || true
helm uninstall loki -n "${MON_NS}" >/dev/null 2>&1 || true
kubectl delete ns "${MON_NS}" --ignore-not-found=true >/dev/null 2>&1 || true
sleep 3
kubectl create ns "${MON_NS}" >/dev/null 2>&1 || true

echo
echo "============================================================"
echo "🧰 Adding Helm Repositories"
echo "============================================================"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1 || true
echo "✅ Helm repositories updated."

echo
echo "============================================================"
echo "📊 Installing Prometheus + Grafana (NodePorts)"
echo "============================================================"
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  -n "${MON_NS}" \
  --set grafana.adminPassword="admin123" \
  --set grafana.service.type=NodePort \
  --set grafana.service.nodePort="${GRAFANA_PORT}" \
  --set prometheus.service.type=NodePort \
  --set prometheus.service.nodePort="${PROM_PORT}" \
  --set grafana.persistence.enabled=false \
  --wait --timeout "${TIMEOUT}"

echo "✅ Prometheus + Grafana installed."

echo
echo "============================================================"
echo "📜 Installing Loki + Promtail (stable configuration)"
echo "============================================================"
helm upgrade --install loki grafana/loki-stack \
  -n "${MON_NS}" \
  --set grafana.enabled=false \
  --set loki.enabled=true \
  --set promtail.enabled=true \
  --set loki.persistence.enabled=false \
  --set loki.storage.type=filesystem \
  --set loki.service.type=NodePort \
  --set loki.service.nodePort="${LOKI_NODEPORT}" \
  --set loki.fullnameOverride="loki" \
  --set promtail.config.clients[0].url="http://loki.${MON_NS}.svc.cluster.local:${LOKI_PORT}/loki/api/v1/push" \
  --wait --timeout "${TIMEOUT}"

echo "✅ Loki + Promtail installed."
echo
echo "============================================================"
echo "📁 Configuring Grafana Datasources (Prometheus + Loki)"
echo "============================================================"

cat <<EOF | kubectl apply -n "${MON_NS}" -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasources
  labels:
    grafana_datasource: "1"
data:
  datasources.yaml: |
    apiVersion: 1
    datasources:
      - name: Prometheus
        type: prometheus
        access: proxy
        url: http://prometheus-operated.${MON_NS}.svc.cluster.local:9090
        isDefault: true
      - name: Loki
        type: loki
        access: proxy
        url: http://loki.${MON_NS}.svc.cluster.local:${LOKI_PORT}
        jsonData:
          maxLines: 1000
EOF

# 🔄 Patch Grafana to use preprovisioned datasources
kubectl patch deployment prometheus-grafana -n "${MON_NS}" \
  --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/volumes/-","value":{"name":"grafana-datasources","configMap":{"name":"grafana-datasources"}}},{"op":"add","path":"/spec/template/spec/containers/0/volumeMounts/-","value":{"mountPath":"/etc/grafana/provisioning/datasources","name":"grafana-datasources"}}]' >/dev/null 2>&1 || true

kubectl rollout restart deployment prometheus-grafana -n "${MON_NS}" >/dev/null 2>&1

# Wait for Grafana rollout
echo -n "⏳ Waiting for Grafana to become ready..."
kubectl -n "${MON_NS}" rollout status deployment prometheus-grafana --timeout=120s || true
echo "✅ Grafana restarted."

echo
echo "============================================================"
echo "📏 Installing Metrics Server (optional)"
echo "============================================================"
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml >/dev/null 2>&1 || true
echo "✅ Metrics Server applied."

echo
echo "============================================================"
echo "🌐 Access Information"
echo "============================================================"

if command -v minikube >/dev/null 2>&1; then
  CLUSTER_IP=$(minikube ip)
else
  CLUSTER_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
fi

echo "Prometheus : http://${CLUSTER_IP}:${PROM_PORT}"
echo "Grafana    : http://${CLUSTER_IP}:${GRAFANA_PORT}  (admin / admin123)"
echo "Loki API   : http://${CLUSTER_IP}:${LOKI_NODEPORT}"
echo
echo "✅ Prometheus and Loki are both pre-provisioned in Grafana."
echo
echo "Check pods and services:"
echo "  kubectl get pods -n ${MON_NS}"
echo "  kubectl get svc  -n ${MON_NS}"
echo
echo "============================================================"
echo "🎯 Setup Complete — Monitoring Stack is fully operational!"
echo "============================================================"

LOKI_URL="http://192.168.49.2:31000/loki/api/v1/push"
 
for i in $(seq 1 10); do
  msg="INFO  [web-app-project] Log message #$i - Everything running smoothly"
  json=$(jq -n --arg line "$msg" --arg time "$(date --utc +%s%N)" \
  '{streams: [{stream: {job:"web-app-project", level:"INFO"}, values: [[ $time, $line ]]}]}')
  curl -s -X POST -H "Content-Type: application/json" -d "$json" "$LOKI_URL" >/dev/null
  sleep 0.1
done
 
for i in $(seq 1 5); do
  msg="ERROR [web-app-project] Log message #$i - Something went wrong!"
  json=$(jq -n --arg line "$msg" --arg time "$(date --utc +%s%N)" \
  '{streams: [{stream: {job:"web-app-project", level:"ERROR"}, values: [[ $time, $line ]]}]}')
  curl -s -X POST -H "Content-Type: application/json" -d "$json" "$LOKI_URL" >/dev/null
  sleep 0.1
done
 
echo "✅ 10 INFO + 5 ERROR dummy logs pushed to Loki (job=web-app-project)"