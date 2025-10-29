#!/bin/bash
set -e

# ============================================================
# 🚀 ArgoCD Blue-Green Project Setup Script
# Author: Smit Darji
# ============================================================

APP_NAME="k8s-app-bg"
APP_NAMESPACE="webapps-bg"
ARGOCD_NAMESPACE="argocd"
GIT_REPO_URL="https://github.com/smit-darji/k8s-argo-bg-cicd.git"
BRANCH="Master"
APP_PATH="bluegreen"

echo "============================================================"
echo "🧹 STEP 1: Remove old Blue-Green application (if exists)"
echo "============================================================"
kubectl delete application k8s-app-bluegreen -n $ARGOCD_NAMESPACE --ignore-not-found=true
kubectl delete namespace webapps --ignore-not-found=true
echo "✅ Old Blue-Green app removed (if it existed)."

echo "============================================================"
echo "📦 STEP 2: Create new namespace for Blue-Green deployment"
echo "============================================================"
kubectl create namespace $APP_NAMESPACE || echo "Namespace already exists"

echo "============================================================"
echo "🚀 STEP 3: Create new ArgoCD Blue-Green Application"
echo "============================================================"
kubectl apply -f argo-app-bg.yaml -n $ARGOCD_NAMESPACE

echo "============================================================"
echo "✅ Blue-Green ArgoCD App Deployed Successfully!"
echo "Check ArgoCD UI at: http://localhost:8080"
echo "Application Name: $APP_NAME"
echo "============================================================"
