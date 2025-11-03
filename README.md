setup:
    init.sh
    init-webapp-bg.sh




kubectl get svc -n webapp-bg
 kubectl get svc -n webapp-bg -o wide
NAME                TYPE       CLUSTER-IP       EXTERNAL-IP   PORT(S)        AGE     SELECTOR
webapp-bg-preview   NodePort   10.106.225.184   <none>        80:31081/TCP   4m38s   app=webapp,version=green
webapp-bg-stable    NodePort   10.98.42.5       <none>        80:31080/TCP   4m38s   app=webapp,version=blue


get proper port of service

kubectl argo rollouts get rollout webapp-bg -n webapp-bg
kubectl get svc -n webapp-bg
kubectl get pods -n webapp-bg -o wide