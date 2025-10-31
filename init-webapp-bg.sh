#!/bin/bash
set -e

# ============================================================
# 🚀 ArgoCD Blue-Green Deployment Setup Script (with 15-min gradual switch)
# Author: Smit Darji
# ============================================================

APP_NAME="webapp-bg"
APP_NAMESPACE="webapp-bg"
ARGOCD_NAMESPACE="argocd"
GIT_REPO_URL="https://github.com/smit-darji/k8s-argo-bg-cicd.git"
BRANCH="Master"
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
echo "🎯 STEP 6: Sync ArgoCD Application"
echo "============================================================"

if command -v argocd &> /dev/null; then
  echo "🔄 Syncing ArgoCD Application..."
  if argocd app sync $APP_NAME --grpc-web; then
    echo "✅ Application synced successfully from repo path: $APP_PATH"
  else
    echo "⚠️ ArgoCD sync failed — check login credentials or repo access."
  fi
else
  echo "ℹ️ ArgoCD CLI not found. Skipping manual sync (it will auto-sync via UI if enabled)."
fi


echo
echo "============================================================"
echo "🌍 STEP 7: Get Application URLs"
echo "============================================================"
STABLE_PORT=$(kubectl get svc ${APP_NAME}-stable -n $APP_NAMESPACE -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "N/A")
PREVIEW_PORT=$(kubectl get svc ${APP_NAME}-preview -n $APP_NAMESPACE -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "N/A")
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[0].address}')

echo
echo "✅ Blue-Green Deployment Active!"
echo "🔵 Stable URL : http://$NODE_IP:$STABLE_PORT"
echo "🟢 Preview URL: http://$NODE_IP:$PREVIEW_PORT"


echo
echo "============================================================"
echo "🌐 STEP 8: Check Rollout Status"
echo "============================================================"
kubectl argo rollouts get rollout $APP_NAME -n $APP_NAMESPACE || echo "ℹ️ Rollout not found yet — wait a few seconds."

echo
echo "============================================================"
echo "✅ Deployment setup complete."
echo "============================================================"
