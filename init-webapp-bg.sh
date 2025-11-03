#!/bin/bash
set -e

# ============================================================
# 🚀 ArgoCD Blue-Green Deployment Script (Full Setup)
# Author: Smit Darji
# ============================================================

APP_NAME="webapp-bg"
APP_NAMESPACE="webapp-bg"
ARGOCD_NAMESPACE="argocd"
GIT_REPO_URL="https://github.com/smit-darji/k8s-argo-bg-cicd.git"
BRANCH="Master"
APP_PATH="bluegreen"

# ============================================================
# 🧹 STEP 1: Cleanup
# ============================================================
echo "🧹 Cleaning previous setup..."
kubectl delete application $APP_NAME -n BRANCH="master"$ARGOCD_NAMESPACE --ignore-not-found=true
kubectl delete namespace $APP_NAMESPACE --ignore-not-found=true
sleep 3
echo "✅ Clean slate ready."

# ============================================================
# 📦 STEP 2: Create Namespace
# ============================================================
echo "📦 Creating namespace: $APP_NAMESPACE"
kubectl create namespace $APP_NAMESPACE || echo "⚠️ Namespace already exists."

# ============================================================
# 🧩 STEP 3: Install Argo Rollouts if missing
# ============================================================
if ! kubectl get crd rollouts.argoproj.io >/dev/null 2>&1; then
  echo "⚙️  Installing Argo Rollouts CRDs and Controller..."
  kubectl apply -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
  echo "⏳ Waiting for Argo Rollouts controller to be ready..."
  sleep 30
else
  echo "✅ Argo Rollouts already installed."
fi

# ============================================================
# 🧰 STEP 4: RBAC Fix (if required)
# ============================================================
echo "🔧 Verifying RBAC..."
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
echo "✅ RBAC fixed."

# ============================================================
# 🚀 STEP 5: Create ArgoCD Application
# ============================================================
echo "🚀 Deploying ArgoCD Application..."
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
echo "✅ ArgoCD Application deployed."

# ============================================================
# 🔑 STEP 6: Login & Sync using ArgoCD CLI
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
  echo "⚠️ ArgoCD CLI not installed. Auto-sync in UI will handle deployment."
fi

# ============================================================
# 🌍 STEP 7: Expose Services (Stable & Preview)
# ============================================================
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[0].address}')
STABLE_PORT=$(kubectl get svc ${APP_NAME}-stable -n $APP_NAMESPACE -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
CANARY_PORT=$(kubectl get svc ${APP_NAME}-canary -n $APP_NAMESPACE -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")

for svc in stable canary; do
  if ! kubectl get svc ${APP_NAME}-${svc} -n $APP_NAMESPACE >/dev/null 2>&1; then
    echo "⚙️ Creating ${APP_NAME}-${svc} service..."
    kubectl expose rollout ${APP_NAME} --name=${APP_NAME}-${svc} --port=80 --target-port=80 --type=NodePort -n $APP_NAMESPACE
  fi
done

STABLE_PORT=$(kubectl get svc ${APP_NAME}-stable -n $APP_NAMESPACE -o jsonpath='{.spec.ports[0].nodePort}')
CANARY_PORT=$(kubectl get svc ${APP_NAME}-canary -n $APP_NAMESPACE -o jsonpath='{.spec.ports[0].nodePort}')

echo
echo "🔵 Stable URL : http://$NODE_IP:$STABLE_PORT"
echo "🟢 Preview URL: http://$NODE_IP:$CANARY_PORT"

# ============================================================
# 📊 STEP 8: Rollout Status
# ============================================================
echo
echo "📊 Checking rollout status..."
kubectl argo rollouts get rollout $APP_NAME -n $APP_NAMESPACE || echo "⚠️ Rollout not ready yet."

echo
echo "✅ Blue-Green Deployment Setup Complete!"
echo "============================================================"
