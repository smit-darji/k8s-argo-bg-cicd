#!/bin/bash
set -e

# ============================================================
# 🚀 ArgoCD Blue-Green Deployment Setup Script for Web Application
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
# This prevents "forbidden: cannot get configmaps" error
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
echo "🚀 STEP 5: Deploy Blue-Green Application via ArgoCD"
echo "============================================================"
kubectl apply -f argo-app-webapp-bg.yaml -n $ARGOCD_NAMESPACE

echo "⏳ Waiting for ArgoCD to sync resources..."
sleep 30

echo
echo "============================================================"
echo "🎯 STEP 6: Apply Rollout and Services (Gradual 15-min traffic shift)"
echo "============================================================"
kubectl apply -f bluegreen/service.yaml -n $APP_NAMESPACE
kubectl apply -f bluegreen/rollout.yaml -n $APP_NAMESPACE

echo
echo "============================================================"
echo "🌐 STEP 7: Expose Service URLs (NodePort)"
echo "============================================================"
STABLE_URL=$(minikube service webapp-bg-stable -n $APP_NAMESPACE --url 2>/dev/null || true)
CANARY_URL=$(minikube service webapp-bg-canary -n $APP_NAMESPACE --url 2>/dev/null || true)

echo "✅ Stable Service URL: ${STABLE_URL:-Not available}"
echo "✅ Canary Service URL: ${CANARY_URL:-Not available}"

echo
echo "============================================================"
echo "🧭 STEP 8: Install Argo Rollouts CLI (if not installed)"
echo "============================================================"
if ! command -v kubectl-argo-rollouts &> /dev/null; then
  echo "⚙️  Installing Argo Rollouts CLI..."
  curl -LO https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-linux-amd64
  sudo install -m 755 kubectl-argo-rollouts-linux-amd64 /usr/local/bin/kubectl-argo-rollouts
  rm -f kubectl-argo-rollouts-linux-amd64
else
  echo "✅ CLI already installed."
fi

echo
echo "============================================================"
echo "📊 STEP 9: Monitor Rollout Status"
echo "============================================================"
kubectl-argo-rollouts get rollout $APP_NAME -n $APP_NAMESPACE --watch
