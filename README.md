---------------------------------------------------
---- for argocd
1. Inside clusterissuer.yaml file , please change the email to your own email
2. Inside argocd-ingress.yaml file , please Change this domain "argocd.seang.shop" to your domain
3. then cd to folder argocd
4. using this command to add the file to kubernete
```bash

    1. kubectl apply -f clusterissuer.yaml

    - wait 30 seconds then run the command

    2. kubectl apply -f argocd-ingress.yaml

```
--- kubernete Dashboard

1. Inside clusterissuer.yaml file , please change the email to your own email
2. Inside certificate-seconde.yaml file , please Change this domain "kubernetes.dashboard.seang.shop" to your domain
3. Inside ingress-kubernete.yaml file , please Change this domain "kubernetes.dashboard.seang.shop" to your domain
4. then cd to folder dashboard-k8s
5. using this command to add the file to kubernete

```bash
    1. kubectl apply -f clusterissuer.yaml

    - wait 30 seconds then run the command

    2. kubectl apply -f certificate-secontion.yaml

     - wait 30 seconds then run the command

    3. kubectl apply -f ingress-kubernete.yaml 
```