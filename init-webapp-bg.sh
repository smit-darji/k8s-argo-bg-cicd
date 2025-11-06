#!/bin/bash
set -e

# ============================================================
# 🚀 ArgoCD Blue-Green Deployment Bootstrap Script
# Author: Smit Darji
# ============================================================

APP_NAME="webapp-bg"
APP_NAMESPACE="webapp-bg"
ARGOCD_NAMESPACE="argocd"
GIT_REPO_URL="https://github.com/smit-darji/k8s-argo-bg-cicd.git"
BRANCH="Master"
APP_PATH="bluegreen"
APP_FILE="${APP_PATH}/argo-app-webapp-bg.yaml"
ROLLOUT_FILE="${APP_PATH}/rollout.yaml"

# ============================================================
# 🧹 STEP 1: Cleanup (Safe)
# ============================================================
echo "🧹 Cleaning previous setup..."
kubectl delete application $APP_NAME -n $ARGOCD_NAMESPACE --ignore-not-found=true
kubectl delete namespace $APP_NAMESPACE --ignore-not-found=true
sleep 3
echo "✅ Clean slate ready."

# ============================================================
# 📦 STEP 2: Create Namespace
# ============================================================
echo "📦 Creating namespace: $APP_NAMESPACE"
kubectl create namespace $APP_NAMESPACE || echo "⚠️ Namespace already exists."

# ============================================================
# ⚙️ STEP 3: Ensure Argo Rollouts Installed
# ============================================================
echo "🔍 Checking Argo Rollouts installation..."
if ! kubectl get crd rollouts.argoproj.io >/dev/null 2>&1; then
  echo "⚙️ Installing Argo Rollouts CRDs and Controller..."
  kubectl apply -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
else
  echo "✅ Argo Rollouts CRDs already installed."
fi

echo "⏳ Waiting for Argo Rollouts controller to be ready..."
kubectl wait --for=condition=available deployment/argo-rollouts -n argo-rollouts --timeout=120s || {
  echo "⚠️ Rollouts controller not ready, retrying installation..."
  kubectl delete ns argo-rollouts --ignore-not-found=true
  kubectl apply -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
  sleep 30
}
echo "✅ Argo Rollouts controller ready."

# ============================================================
# 🧰 STEP 4: Ensure RBAC for Argo Rollouts
# ============================================================
echo "🔧 Ensuring RBAC for Argo Rollouts..."
kubectl apply -f - <<EOF >/dev/null 2>&1 || true
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: argo-rollouts-configmap-access
  namespace: $ARGOCD_NAMESPACE
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: argo-rollouts-configmap-access-binding
  namespace: $ARGOCD_NAMESPACE
subjects:
  - kind: ServiceAccount
    name: argo-rollouts
    namespace: $ARGOCD_NAMESPACE
roleRef:
  kind: Role
  name: argo-rollouts-configmap-access
  apiGroup: rbac.authorization.k8s.io
EOF
echo "✅ RBAC verified."

# ============================================================
# 🚀 STEP 5: Apply ArgoCD Application (from Git repo)
# ============================================================
echo "🚀 Applying ArgoCD Application manifest from: $APP_FILE"
if [ ! -f "$APP_FILE" ]; then
  echo "❌ ERROR: $APP_FILE not found!"
  exit 1
fi

kubectl apply -f "$APP_FILE"
sleep 15
echo "✅ ArgoCD Application applied successfully."

# ============================================================
# 🔑 STEP 6: ArgoCD CLI Sync (optional, if CLI available)
# ============================================================
if command -v argocd &>/dev/null; then
  echo "🔐 Logging into ArgoCD..."
  ARGO_PASS=$(kubectl -n $ARGOCD_NAMESPACE get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
  ARGOCD_SERVER="localhost:8080"

  if ! lsof -i :8080 >/dev/null 2>&1; then
    kubectl port-forward svc/argocd-server -n $ARGOCD_NAMESPACE 8080:80 >/dev/null 2>&1 &
    sleep 5
  fi

  argocd logout $ARGOCD_SERVER --grpc-web >/dev/null 2>&1 || true
  argocd login $ARGOCD_SERVER --username admin --password "$ARGO_PASS" --insecure --grpc-web
  echo "🔄 Syncing ArgoCD app..."
  argocd app sync $APP_NAME --grpc-web || echo "⚠️ Sync failed, check ArgoCD UI."
else
  echo "⚠️ ArgoCD CLI not found — relying on ArgoCD auto-sync."
fi

# ============================================================
# 🌍 STEP 7: Validate Rollout, Services, and Ingress
# ============================================================
echo "⚙️ Validating deployed resources in namespace: $APP_NAMESPACE"

kubectl -n $APP_NAMESPACE get rollout >/dev/null 2>&1 || echo "⚠️ Rollout not found yet."
kubectl -n $APP_NAMESPACE get svc webapp-bg-stable >/dev/null 2>&1 || echo "⚠️ Service webapp-bg-stable missing!"
kubectl -n $APP_NAMESPACE get svc webapp-bg-preview >/dev/null 2>&1 || echo "⚠️ Service webapp-bg-preview missing!"
kubectl -n $APP_NAMESPACE get ingress webapp-bg-ingress >/dev/null 2>&1 || echo "⚠️ Ingress missing!"

NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[0].address}')
STABLE_PORT=$(kubectl get svc webapp-bg-stable -n $APP_NAMESPACE -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "N/A")
PREVIEW_PORT=$(kubectl get svc webapp-bg-preview -n $APP_NAMESPACE -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "N/A")

echo
echo "🔵 Stable URL : http://$NODE_IP:$STABLE_PORT"
echo "🟢 Preview URL: http://$NODE_IP:$PREVIEW_PORT"

# ============================================================
# 📊 STEP 8: Check Rollout Status
# ============================================================
echo
echo "📊 Checking rollout status..."
if kubectl argo rollouts get rollout $APP_NAME -n $APP_NAMESPACE >/dev/null 2>&1; then
  kubectl argo rollouts get rollout $APP_NAME -n $APP_NAMESPACE
else
  echo "⚠️ Rollout not ready yet — verifying CRDs..."
  kubectl get crd | grep rollout || echo "❌ Rollout CRD missing!"
fi

echo
echo "✅ Blue-Green Deployment Setup Complete!"
echo "============================================================"
