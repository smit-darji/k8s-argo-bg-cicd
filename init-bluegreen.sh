#!/bin/bash
set -e

# ============================================================
# 🚀 ArgoCD Blue-Green Project Setup Script
# Author: Smit Darji
# ============================================================

APP_NAME="k8s-app-bluegreen"
APP_NAMESPACE="webapps"
ARGOCD_NAMESPACE="argocd"
GIT_REPO_URL="https://github.com/smit-darji/kubernetes-cicd.git"
BRANCH="Master"
APP_PATH="bluegreen"

echo "============================================================"
echo "🔹 Creating Blue-Green ArgoCD Application"
echo "============================================================"

kubectl apply -f argo-app-bg.yaml -n $ARGOCD_NAMESPACE

echo "============================================================"
echo "✅ Blue-Green ArgoCD App Deployed Successfully!"
echo "Check ArgoCD UI at: http://localhost:8080"
echo "Application Name: $APP_NAME"
echo "============================================================"
