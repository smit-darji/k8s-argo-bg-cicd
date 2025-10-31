kubectl get svc -n webapp-bg
minikube service webapp-bg-stable -n webapp-bg --url
minikube service webapp-bg-canary -n webapp-bg --url
