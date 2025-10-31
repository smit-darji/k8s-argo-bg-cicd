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
echo "🚀 STEP 3: Deploy Blue-Green Application via ArgoCD"
echo "============================================================"
kubectl apply -f argo-app-webapp-bg.yaml -n $ARGOCD_NAMESPACE

echo "⏳ Waiting for ArgoCD to sync resources..."
sleep 20

echo "============================================================"
echo "🎯 STEP 4: Apply Rollout (Gradual 15-minute traffic shift)"
echo "============================================================"
kubectl apply -f bluegreen/service.yaml -n $APP_NAMESPACE
kubectl apply -f bluegreen/rollout.yaml -n $APP_NAMESPACE

echo "============================================================"
echo "✅ Rollout initiated. Monitoring progress..."
echo "============================================================"
kubectl argo rollouts get rollout $APP_NAME -n $APP_NAMESPACE --watch
