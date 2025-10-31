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
# Prevents "forbidden: cannot get configmaps" error
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
sleep 30
echo "✅ ArgoCD Application synced."

echo
echo "============================================================"
echo "🎯 STEP 6: Create Blue-Green Rollout (15-min Gradual Traffic Shift)"
echo "============================================================"
cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: $APP_NAME
  namespace: $APP_NAMESPACE
spec:
  replicas: 3
  strategy:
    blueGreen:
      activeService: ${APP_NAME}-stable
      previewService: ${APP_NAME}-preview
      autoPromotionEnabled: true
      autoPromotionSeconds: 900  # 15 min = 900 seconds
  selector:
    matchLabels:
      app: $APP_NAME
  template:
    metadata:
      labels:
        app: $APP_NAME
    spec:
      containers:
      - name: $APP_NAME
        image: smitdarji/k8s:v1.0.0
        ports:
        - containerPort: 80
EOF

echo
echo "============================================================"
echo "🌐 STEP 7: Create Services (Stable & Preview)"
echo "============================================================"
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: ${APP_NAME}-stable
  namespace: $APP_NAMESPACE
spec:
  type: NodePort
  selector:
    app: $APP_NAME
  ports:
    - port: 80
      targetPort: 80
      protocol: TCP
---
apiVersion: v1
kind: Service
metadata:
  name: ${APP_NAME}-preview
  namespace: $APP_NAMESPACE
spec:
  type: NodePort
  selector:
    app: $APP_NAME
  ports:
    - port: 80
      targetPort: 80
      protocol: TCP
EOF

echo
echo "============================================================"
echo "🧭 STEP 8: Install Argo Rollouts CLI (if missing)"
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
echo "📊 STEP 9: Monitor Rollout Gradual Promotion"
echo "============================================================"
kubectl-argo-rollouts get rollout $APP_NAME -n $APP_NAMESPACE --watch
