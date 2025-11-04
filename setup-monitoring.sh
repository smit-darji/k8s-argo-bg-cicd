#!/bin/bash
set -euo pipefail

# ============================================================
# 🚀 Complete Kubernetes Monitoring Setup
# Prometheus + Grafana + Metrics Server
# Works with Minikube / ArgoCD / Local Clusters
# Author: Smit Darji (fixed)
# ============================================================

MON_NS="monitoring"
PROM_PORT=30090
GRAFANA_PORT=30300

# helper: safe command exist check
_has() { command -v "$1" >/dev/null 2>&1; }

# ============================================================
# 🧹 STEP 1: Safe Cleanup (only if namespace exists)
# ============================================================
echo
echo "============================================================"
echo "🧹 STEP 1: Cleaning Previous Monitoring Setup (Safe)"
echo "============================================================"

if kubectl get namespace "$MON_NS" >/dev/null 2>&1; then
  echo "🗑️  Cleaning existing namespace and Helm releases..."
  # Try uninstall releases if present (ignore error)
  helm uninstall prometheus -n "$MON_NS" 2>/dev/null || true
  helm uninstall grafana -n "$MON_NS" 2>/dev/null || true

  # Delete namespace (non-blocking); handle finalizers if stuck
  kubectl delete namespace "$MON_NS" --ignore-not-found=true --wait=false || true
  sleep 5

  # If namespace stuck in Terminating, remove finalizers (requires jq)
  if kubectl get ns "$MON_NS" -o jsonpath='{.status.phase}' 2>/dev/null | grep -q "Terminating"; then
    echo "⚠️  Namespace stuck — attempting to remove finalizers..."
    if _has jq; then
      kubectl get ns "$MON_NS" -o json | jq 'del(.spec.finalizers)' | \
        kubectl replace --raw "/api/v1/namespaces/$MON_NS/finalize" -f - >/dev/null 2>&1 || true
      echo "✅ finalizers removed (if any)."
    else
      echo "⚠️ jq not found; cannot remove namespace finalizers. Install jq or remove finalizers manually."
    fi
  fi

  echo "✅ Namespace cleanup complete (or in progress)."
else
  echo "ℹ️  No existing namespace found — skipping cleanup."
fi

# ============================================================
# 🧩 STEP 2: Install Metrics Server
# ============================================================
echo
echo "============================================================"
echo "🧩 STEP 2: Installing Metrics Server (Required for Pod/Node Metrics)"
echo "============================================================"

# Apply metrics-server manifest (retry once if needed)
if ! kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml; then
  echo "⚠️ Initial metrics-server install failed — retrying in 5s..."
  sleep 5
  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
fi

# Patch metrics-server deployment for local clusters (idempotent)
# Add the args only if not present to avoid repeated patches
MS_DEPLOY="deployment/metrics-server"
if kubectl -n kube-system get "$MS_DEPLOY" >/dev/null 2>&1; then
  if ! kubectl -n kube-system get "$MS_DEPLOY" -o jsonpath='{.spec.template.spec.containers[0].args[*]}' 2>/dev/null | \
       grep -q -- '--kubelet-insecure-tls'; then
    echo "🔧 Patching metrics-server args for local cluster compatibility..."
    kubectl -n kube-system patch "$MS_DEPLOY" --type='json' \
      -p='[{"op":"add","path":"/spec/template/spec/containers/0/args","value":["--kubelet-insecure-tls","--kubelet-preferred-address-types=InternalIP,Hostname,ExternalIP"]}]' || true
  else
    echo "ℹ️ metrics-server already patched; skipping."
  fi
else
  echo "⚠️ metrics-server deployment not found in kube-system — continuing anyway."
fi

echo "✅ Metrics Server installed and patched (if present)."
sleep 8

# ============================================================
# 📦 STEP 3: Create Monitoring Namespace (idempotent)
# ============================================================
echo
echo "============================================================"
echo "📦 STEP 3: Creating Monitoring Namespace"
echo "============================================================"
kubectl create namespace "$MON_NS" >/dev/null 2>&1 || echo "ℹ️ Namespace '$MON_NS' already exists."

# ============================================================
# 🧭 STEP 4: Add & Update Helm Repositories
# ============================================================
echo
echo "============================================================"
echo "🧭 STEP 4: Adding Helm Repositories"
echo "============================================================"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1 || true
echo "✅ Helm repositories added/updated."

# ============================================================
# 📈 STEP 5: Install Prometheus Stack
# ============================================================
echo
echo "============================================================"
echo "📈 STEP 5: Installing Prometheus Stack"
echo "============================================================"

# Use recommended Helm value overrides to reduce CRD / admission webhook warnings
# - disable admission webhooks (avoids webhook-related log spam for local clusters)
# - disable cert-manager integration/tls for operator webhooks (local clusters)
# - turn off built-in grafana/alertmanager as we install grafana separately
# Note: keep --wait to ensure charts are deployed before continuing
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace "$MON_NS" \
  --set prometheus.service.type=NodePort \
  --set prometheus.service.nodePort="$PROM_PORT" \
  --set grafana.enabled=false \
  --set alertmanager.enabled=false \
  --set kubeStateMetrics.enabled=true \
  --set nodeExporter.enabled=true \
  --set prometheusOperator.admissionWebhooks.enabled=false \
  --set prometheusOperator.admissionWebhooks.patch.enabled=false \
  --set prometheusOperator.tls.enabled=false \
  --set prometheusOperator.admissionWebhooks.failurePolicy=Ignore \
  --set global.ruleValidation=false \
  --wait

echo "✅ Prometheus (kube-prometheus-stack) installed/upgraded successfully."

# Resolve Prometheus access host (minikube fallback)
MINIKUBE_IP=""
if _has minikube; then
  set +e
  MINIKUBE_IP=$(minikube ip 2>/dev/null || true)
  set -e
fi
# If minikube not available or returned empty, attempt node IP fallback
if [ -z "$MINIKUBE_IP" ]; then
  # try to get any node external/internal IP
  MINIKUBE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || true)
fi
PROM_URL="http://${MINIKUBE_IP:-127.0.0.1}:$PROM_PORT"
echo "🌍 Prometheus URL (approx): $PROM_URL"

# ============================================================
# 📊 STEP 6: Install Grafana (Linked to Prometheus)
# ============================================================
echo
echo "============================================================"
echo "📊 STEP 6: Installing Grafana Dashboard (Linked to Prometheus)"
echo "============================================================"

# Use stable datasource config via values; ensure datasources key quoting is correct for Helm CLI
helm upgrade --install grafana grafana/grafana \
  --namespace "$MON_NS" \
  --set service.type=NodePort \
  --set service.nodePort="$GRAFANA_PORT" \
  --set persistence.enabled=false \
  --set adminUser='admin' \
  --set adminPassword='admin123' \
  --set "datasources.datasources\\.yaml.apiVersion"=1 \
  --set "datasources.datasources\\.yaml.datasources[0].name"=Prometheus \
  --set "datasources.datasources\\.yaml.datasources[0].type"=prometheus \
  --set "datasources.datasources\\.yaml.datasources[0].url"="http://prometheus-kube-prometheus-prometheus.${MON_NS}.svc.cluster.local:9090" \
  --set "datasources.datasources\\.yaml.datasources[0].access"=proxy \
  --set "datasources.datasources\\.yaml.datasources[0].isDefault"=true \
  --wait

echo "✅ Grafana installed/upgraded successfully."

GRAF_URL="http://${MINIKUBE_IP:-127.0.0.1}:$GRAFANA_PORT"
echo "🌍 Grafana URL (approx): $GRAF_URL"
echo "👤 Login: admin | 🔑 Password: admin123"

# ============================================================
# ⏳ STEP 7: Wait for Monitoring Pods (robust)
# ============================================================
echo
echo "============================================================"
echo "⏳ STEP 7: Waiting for Prometheus, Grafana & Metrics Pods"
echo "============================================================"

# Wait for all pods in monitoring namespace to be ready (safer / more general)
kubectl wait --for=condition=ready pod --all -n "$MON_NS" --timeout=300s || {
  echo "⚠️ Some pods in $MON_NS are not ready within timeout. Showing pod status:"
  kubectl get pods -n "$MON_NS" -o wide || true
}

# Wait for metrics-server in kube-system (if present)
if kubectl -n kube-system get deployment metrics-server >/dev/null 2>&1; then
  kubectl wait --for=condition=available deployment/metrics-server -n kube-system --timeout=180s || true
fi

# ============================================================
# 🔍 STEP 8: Show Deployment Status
# ============================================================
echo
echo "============================================================"
echo "🔍 STEP 8: Monitoring Deployment Status"
echo "============================================================"
kubectl get pods -n "$MON_NS" -o wide || true
kubectl get svc -n "$MON_NS" || true

# ============================================================
# 📉 STEP 9: Verify Metrics Availability
# ============================================================
echo
echo "============================================================"
echo "📉 STEP 9: Verifying Node & Pod Metrics"
echo "============================================================"
if kubectl top nodes >/dev/null 2>&1; then
  kubectl top nodes
else
  echo "⚠️ Node metrics not yet available (kubectl top nodes failed). Waiting few seconds and re-checking..."
  sleep 8
  kubectl top nodes || echo "⚠️ Node metrics still unavailable. Ensure metrics-server is running and kubelet allows metrics."
fi

if kubectl top pods -A >/dev/null 2>&1; then
  kubectl top pods -A
else
  echo "⚠️ Pod metrics not yet available. Re-checking..."
  sleep 6
  kubectl top pods -A || echo "⚠️ Pod metrics still unavailable."
fi

echo "✅ Metrics collection check complete (if metrics-server is healthy)."

# ============================================================
# ✅ STEP 10: Summary
# ============================================================
echo
echo "============================================================"
echo "✅ Kubernetes Monitoring Setup Complete!"
echo "============================================================"
echo "🔗 Prometheus → $PROM_URL"
echo "🔗 Grafana → $GRAF_URL"
echo "👤 Username: admin"
echo "🔑 Password: admin123"
echo "============================================================"
