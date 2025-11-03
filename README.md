setup:
    init.sh
    init-webapp-bg.sh




kubectl get svc -n webapp-bg
minikube service webapp-bg-stable -n webapp-bg --url
minikube service webapp-bg-canary -n webapp-bg --url


kubectl argo rollouts get rollout webapp-bg -n webapp-bg
kubectl get svc -n webapp-bg
kubectl get pods -n webapp-bg -o wide