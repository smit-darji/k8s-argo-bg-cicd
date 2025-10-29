#!/bin/bash
set -e

# ============================================================
# 🚀 ArgoCD + Helm + Minikube Setup Script
# Author: Smit Darji
# ============================================================

# --- CONFIG ---
APP_NAME="my-app"
APP_NAMESPACE="webapps"
GIT_REPO_URL="https://github.com/<your-username>/<your-repo>.git"   # ✅ Change this
HELM_PATH="helm"                                                    # path to your chart folder
ARGOCD_NAMESPACE="argocd"

echo "============================================================"
echo "🔹 STEP 1: Start Minikube"
echo "============================================================"
minikube start --driver=docker

echo "============================================================"
echo "🔹 STEP 2: Install Helm (if not installed)"
echo "============================================================"
if ! command -v helm &> /dev/null; then
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
else
  echo "✅ Helm already installed"
fi

echo "============================================================"
echo "🔹 STEP 3: Add Argo Helm repo"
echo "============================================================"
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

echo "============================================================"
echo "🔹 STEP 4: Create ArgoCD namespace"
echo "============================================================"
kubectl create namespace $ARGOCD_NAMESPACE || echo "Namespace already exists"

echo "============================================================"
echo "🔹 STEP 5: Install ArgoCD using Helm"
echo "============================================================"

if helm status argocd -n $ARGOCD_NAMESPACE >/dev/null 2>&1; then
  echo "✅ ArgoCD already installed. Skipping Helm install."
else
  helm install argocd argo/argo-cd --namespace $ARGOCD_NAMESPACE
fi


echo "============================================================"
echo "🔹 STEP 6: Wait for ArgoCD Pods to be ready"
echo "============================================================"
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n $ARGOCD_NAMESPACE

echo "============================================================"
echo "🔹 STEP 7: Get ArgoCD Admin Password"
echo "============================================================"
ARGO_PASS=$(kubectl -n $ARGOCD_NAMESPACE get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo ""
echo "============================================================"
echo "✅ ArgoCD Admin Password: $ARGO_PASS"
echo "============================================================"
echo "UI: http://localhost:8080"
echo ""

echo "============================================================"
echo "🔹 STEP 8: Port Forwarding ArgoCD UI"
echo "============================================================"
echo "💡 Open a new terminal if you want to keep it running"
echo "Use: kubectl port-forward svc/argocd-server -n $ARGOCD_NAMESPACE 8080:80"
echo ""
kubectl port-forward svc/argocd-server -n $ARGOCD_NAMESPACE 8080:80 &

# ============================================================
# (OPTIONAL) STEP 9: Connect Repo and Create App in ArgoCD
# Uncomment below lines after first login to ArgoCD UI and setting a new password
# ============================================================

# echo "🔹 STEP 9: Create ArgoCD App for CI/CD"
# argocd login localhost:8080 --username admin --password $ARGO_PASS --insecure
# argocd repo add $GIT_REPO_URL --username <your-username> --password <your-token>
# argocd app create $APP_NAME \
#   --repo $GIT_REPO_URL \
#   --path $HELM_PATH \
#   --dest-server https://kubernetes.default.svc \
#   --dest-namespace $APP_NAMESPACE \
#   --sync-policy automated
# echo "✅ ArgoCD app created successfully!"

echo "============================================================"
echo "🎯 SETUP COMPLETE!"
echo "Login ArgoCD UI → http://localhost:8080"
echo "User: admin"
echo "Password: $ARGO_PASS"
echo "============================================================"
