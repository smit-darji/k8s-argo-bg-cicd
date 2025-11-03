#!/bin/bash
set -e

# ============================================================
# 🚀 Prometheus + Grafana Setup Script for Kubernetes Monitoring
# Author: Smit Darji
# ============================================================

MON_NS="monitoring"

echo "============================================================"
echo "📦 STEP 1: Create monitoring namespace"
echo "============================================================"
kubectl create namespace $MON_NS || echo "Namespace already exists"

echo
echo "============================================================"
echo "🧭 STEP 2: Add and update Helm repos"
echo "============================================================"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

echo
echo "============================================================"
echo "📈 STEP 3: Install Prometheus (Node & Pod metrics)"
echo "============================================================"
helm install prometheus prometheus-community/prometheus \
  --namespace $MON_NS \
  --set server.service.type=NodePort \
  --set server.service.nodePort=30090 \
  --set alertmanager.persistentVolume.enabled=false \
  --set server.persistentVolume.enabled=false

echo "✅ Prometheus installed."
echo "🌍 Access Prometheus at: http://$(minikube ip):30090"

echo
echo "============================================================"
echo "📊 STEP 4: Install Grafana"
echo "============================================================"
helm install grafana grafana/grafana \
  --namespace $MON_NS \
  --set service.type=NodePort \
  --set service.nodePort=30300 \
  --set persistence.enabled=false \
  --set adminPassword='admin123' \
  --set datasources."datasources\.yaml".apiVersion=1 \
  --set datasources."datasources\.yaml".datasources[0].name=Prometheus \
  --set datasources."datasources\.yaml".datasources[0].type=prometheus \
  --set datasources."datasources\.yaml".datasources[0].url=http://prometheus-server.$MON_NS.svc.cluster.local \
  --set datasources."datasources\.yaml".datasources[0].access=proxy \
  --set datasources."datasources\.yaml".datasources[0].isDefault=true

echo "✅ Grafana installed."
echo "🌍 Access Grafana at: http://$(minikube ip):30300"
echo "👤 Login → user: admin | password: admin123"

echo
echo "============================================================"
echo "🧩 STEP 5: Wait for pods to be ready"
echo "============================================================"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=prometheus -n $MON_NS --timeout=180s || true
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n $MON_NS --timeout=180s || true

echo
echo "============================================================"
echo "📉 STEP 6: Verify Prometheus & Grafana Pods"
echo "============================================================"
kubectl get pods -n $MON_NS

echo
echo "============================================================"
echo "✅ Setup Complete!"
echo "============================================================"
echo "🔗 Prometheus → http://$(minikube ip):30090"
echo "🔗 Grafana → http://$(minikube ip):30300"
echo "   Username: admin"
echo "   Password: admin123"
echo "============================================================"
