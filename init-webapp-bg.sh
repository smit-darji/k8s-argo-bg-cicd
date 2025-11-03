#!/bin/bash
set -e

# ============================================================
# 🚀 ArgoCD Blue-Green Deployment Script (Self-Healing)
# Author: Smit Darji
# ============================================================

APP_NAME="webapp-bg"
APP_NAMESPACE="webapp-bg"
ARGOCD_NAMESPACE="argocd"
GIT_REPO_URL="https://github.com/smit-darji/k8s-argo-bg-cicd.git"
BRANCH="master"
APP_PATH="bluegreen"

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
  echo "⚙️  Installing Argo Rollouts CRDs and Controller..."
  kubectl apply -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
else
  echo "✅ Argo Rollouts CRDs already installed."
fi

# Wait for rollout controller pod to start
echo "⏳ Waiting for Argo Rollouts controller to be ready..."
kubectl wait --for=condition=available deployment/argo-rollouts -n argo-rollouts --timeout=120s || {
  echo "⚠️ Rollouts controller not ready, trying to reinstall..."
  kubectl delete ns argo-rollouts --ignore-not-found=true
  kubectl apply -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
  sleep 30
}
echo "✅ Argo Rollouts controller ready."

# Verify Rollout kind is available
if ! kubectl explain rollout >/dev/null 2>&1; then
  echo "❌ Rollout kind not registered — reinstalling CRDs..."
  kubectl apply -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
  sleep 20
fi

# ============================================================
# 🧰 STEP 4: Fix RBAC (if needed)
# ============================================================
echo "🔧 Ensuring RBAC for Argo Rollouts..."
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
echo "✅ RBAC verified."

# ============================================================
# 🚀 STEP 5: Create ArgoCD Application
# ============================================================
echo "🚀 Creating ArgoCD Application..."
cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: $APP_NAME
  namespace: $ARGOCD_NAMESPACE
spec:
  project: default
  source:
    repoURL: $GIT_REPO_URL
    targetRevision: $BRANCH
    path: $APP_PATH
  destination:
    server: https://kubernetes.default.svc
    namespace: $APP_NAMESPACE
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF
sleep 20
echo "✅ ArgoCD Application created."

# ============================================================
# 🔑 STEP 6: ArgoCD CLI Sync (if installed)
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
  echo "⚠️ ArgoCD CLI not installed. Auto-sync will handle deployment."
fi

# ============================================================
# 🌍 STEP 7: Expose Stable & Preview Services
# ============================================================
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[0].address}')
for svc in stable preview; do
  if ! kubectl get svc ${APP_NAME}-${svc} -n $APP_NAMESPACE >/dev/null 2>&1; then
    echo "⚙️ Creating ${APP_NAME}-${svc} service..."
    kubectl expose rollout ${APP_NAME} --name=${APP_NAME}-${svc} --port=80 --target-port=80 --type=NodePort -n $APP_NAMESPACE || true
  fi
done

STABLE_PORT=$(kubectl get svc ${APP_NAME}-stable -n $APP_NAMESPACE -o jsonpath='{.spec.ports[0].nodePort}')
PREVIEW_PORT=$(kubectl get svc ${APP_NAME}-preview -n $APP_NAMESPACE -o jsonpath='{.spec.ports[0].nodePort}')

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
  echo "⚠️ Rollout not ready yet, verifying CRDs..."
  kubectl get crd | grep rollout || echo "❌ Rollout CRD missing!"
fi

echo
echo "✅ Blue-Green Deployment Setup Complete!"
echo "============================================================"
