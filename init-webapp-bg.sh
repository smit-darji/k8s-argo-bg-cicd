#!/bin/bash
set -e

# ============================================================
# 🚀 ArgoCD Blue-Green Project Setup Script for WebApplication
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

echo "============================================================"
echo "📦 STEP 2: Create fresh namespace"
echo "============================================================"
kubectl create namespace $APP_NAMESPACE || echo "Namespace already exists"

echo "============================================================"
echo "🧩 STEP 3: Verify Argo Rollouts installation"
echo "============================================================"
if ! kubectl get crd rollouts.argoproj.io >/dev/null 2>&1; then
  echo "⚙️  Installing Argo Rollouts CRDs and Controller..."
  kubectl apply -n $ARGOCD_NAMESPACE -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
  echo "⏳ Waiting for Argo Rollouts controller to be ready..."
  sleep 25
else
  echo "✅ Argo Rollouts already installed."
fi

echo "============================================================"
echo "🚀 STEP 4: Deploy Blue-Green Application via ArgoCD"
echo "============================================================"
kubectl apply -f argo-app-webapp-bg.yaml -n $ARGOCD_NAMESPACE

echo "⏳ Waiting for ArgoCD to sync resources..."
sleep 30

echo "============================================================"
echo "🎯 STEP 5: Apply Rollout (Gradual 15-minute traffic shift)"
echo "============================================================"
kubectl apply -f bluegreen/service.yaml -n $APP_NAMESPACE
kubectl apply -f bluegreen/rollout.yaml -n $APP_NAMESPACE

echo "============================================================"
echo "🌐 STEP 6: Expose Service URLs (NodePort)"
echo "============================================================"
STABLE_URL=$(minikube service webapp-bg-stable -n $APP_NAMESPACE --url 2>/dev/null || true)
CANARY_URL=$(minikube service webapp-bg-canary -n $APP_NAMESPACE --url 2>/dev/null || true)

echo "✅ Stable Service URL: ${STABLE_URL:-Not available}"
echo "✅ Canary Service URL: ${CANARY_URL:-Not available}"

echo "============================================================"
echo "✅ STEP 7: Rollout Monitoring"
echo "============================================================"

# Ensure Argo Rollouts CLI is installed
if ! command -v kubectl-argo-rollouts &> /dev/null; then
  echo "⚙️  Installing Argo Rollouts CLI..."
  curl -LO https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-linux-amd64
  sudo install -m 755 kubectl-argo-rollouts-linux-amd64 /usr/local/bin/kubectl-argo-rollouts
fi

echo "⏳ Watching rollout status..."
kubectl-argo-rollouts get rollout $APP_NAME -n $APP_NAMESPACE --watch
