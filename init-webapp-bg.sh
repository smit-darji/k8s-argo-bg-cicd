#!/bin/bash
set -e

# ============================================================
# 🚀 ArgoCD Blue-Green Deployment Setup Script (Stable & Preview)
# Author: Smit Darji
# ============================================================

APP_NAME="webapp-bg"
APP_NAMESPACE="webapp-bg"
ARGOCD_NAMESPACE="argocd"
GIT_REPO_URL="https://github.com/smit-darji/k8s-argo-bg-cicd.git"
BRANCH="main"
APP_PATH="bluegreen"

echo "============================================================"
echo "🧹 STEP 1: Cleaning up old deployments (if any)"
echo "============================================================"
kubectl delete application $APP_NAME -n $ARGOCD_NAMESPACE --ignore-not-found=true
kubectl delete namespace $APP_NAMESPACE --ignore-not-found=true
echo "✅ Old ArgoCD app and namespace cleaned."

echo
echo "============================================================"
echo "📦 STEP 2: Create fresh namespace"
echo "============================================================"
kubectl create namespace $APP_NAMESPACE || echo "Namespace already exists"
echo "✅ Namespace ready: $APP_NAMESPACE"

echo
echo "============================================================"
echo "🧩 STEP 3: Verify Argo Rollouts installation"
echo "============================================================"
if ! kubectl get crd rollouts.argoproj.io >/dev/null 2>&1; then
  echo "⚙️  Installing Argo Rollouts CRDs and Controller..."
  kubectl apply -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml -n $ARGOCD_NAMESPACE
  echo "⏳ Waiting for Argo Rollouts controller to be ready..."
  sleep 25
else
  echo "✅ Argo Rollouts already installed."
fi

echo
echo "============================================================"
echo "🛠️  STEP 4: Fix Argo Rollouts RBAC (if needed)"
echo "============================================================"
cat <<EOF | kubectl apply -f -
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
echo "✅ Fixed Argo Rollouts RBAC access."

echo
echo "============================================================"
echo "🚀 STEP 5: Deploy ArgoCD Application for Blue-Green"
echo "============================================================"
kubectl apply -f argo-app-webapp-bg.yaml -n $ARGOCD_NAMESPACE
sleep 20
echo "✅ ArgoCD Application created."

echo
echo "============================================================"
echo "🎯 STEP 6: Sync ArgoCD Application via CLI"
echo "============================================================"

if command -v argocd &> /dev/null; then
  echo "🔑 Attempting ArgoCD login..."
  
  # Get ArgoCD password
  ARGO_PASS=$(kubectl -n $ARGOCD_NAMESPACE get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
  
  # Start port-forward in background (if not already running)
  if ! lsof -i :8080 >/dev/null 2>&1; then
    kubectl port-forward svc/argocd-server -n $ARGOCD_NAMESPACE 8080:80 >/dev/null 2>&1 &
    sleep 5
  fi
  
  ARGOCD_SERVER="localhost:8080"
  
  # Clean existing session to prevent invalid token
  argocd logout $ARGOCD_SERVER --grpc-web >/dev/null 2>&1 || true
  
  # Login
  argocd login $ARGOCD_SERVER --username admin --password "$ARGO_PASS" --insecure --grpc-web || {
    echo "❌ Failed to login to ArgoCD. Check that port-forwarding and password are correct."
    exit 1
  }

  # Sync application
  echo "🔄 Syncing ArgoCD Application..."
  if argocd app sync $APP_NAME --grpc-web; then
    echo "✅ Application synced successfully from repo path: $APP_PATH"
  else
    echo "⚠️ ArgoCD sync failed — check login credentials or repo access."
  fi
else
  echo "ℹ️ ArgoCD CLI not found — auto-sync in UI will apply manifests."
fi

echo
echo "============================================================"
echo "🌍 STEP 7: Get Application URLs"
echo "============================================================"
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[0].address}')

# Get ports
STABLE_PORT=$(kubectl get svc ${APP_NAME}-stable -n $APP_NAMESPACE -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
PREVIEW_PORT=$(kubectl get svc ${APP_NAME}-preview -n $APP_NAMESPACE -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
CANARY_PORT=$(kubectl get svc ${APP_NAME}-canary -n $APP_NAMESPACE -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)

# Patch preview/canary service if missing
for svc in preview canary; do
  if ! kubectl get svc ${APP_NAME}-$svc -n $APP_NAMESPACE >/dev/null 2>&1; then
    echo "⚙️  Creating missing ${APP_NAME}-$svc service..."
    kubectl expose deployment ${APP_NAME}-$svc \
      --port=80 --target-port=80 --type=NodePort -n $APP_NAMESPACE || true
  fi
done

[[ -z "$STABLE_PORT" ]] && STABLE_PORT="Unavailable"
[[ -z "$PREVIEW_PORT" ]] && PREVIEW_PORT="Unavailable"
[[ -z "$CANARY_PORT" ]] && CANARY_PORT="Unavailable"

echo
echo "✅ Blue-Green Deployment Active!"
echo "🔵 Stable URL : http://$NODE_IP:$STABLE_PORT"
echo "🟢 Preview URL: http://$NODE_IP:$PREVIEW_PORT"
echo "🟣 Canary URL : http://$NODE_IP:$CANARY_PORT"

echo
echo "============================================================"
echo "🌐 STEP 8: Check Rollout Status"
echo "============================================================"
kubectl argo rollouts get rollout $APP_NAME -n $APP_NAMESPACE || echo "ℹ️ Rollout not found yet — wait a few seconds."

echo
echo "============================================================"
echo "✅ Deployment setup complete."
echo "============================================================"
