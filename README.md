# Stanley Bank K8s Manifests

ArgoCD watches this repository. The CI/CD pipelines in
[`stanley-bank`](https://github.com/Stanleyoluebube/stanley-bank) and
[`stanley-bank-server`](https://github.com/Stanleyoluebube/stanley-bank-server)
commit updated image tags here on every push to `main`, and ArgoCD syncs the
cluster to match.

## Layout

```
bank-project/                    # ArgoCD-tracked; auto-synced
  frontend-deployment.yaml       # Next.js (3 replicas)
  frontend-service.yaml
  frontend-ingress.yaml           # app.stanleybank.site (ALB)
  backend-deployment.yaml         # Express (2 replicas)
  backend-service.yaml
  backend-ingress.yaml            # api.stanleybank.site (ALB)
  configmap.yaml
  secret.yaml                     # DB credentials (operator-populated)
  app-secrets.yaml                # JWT_SECRET
  cluster-issuer.yaml             # Let's Encrypt
  ingress-argocd.yaml             # argocd.stanleybank.site (nginx)
  argocd-namespace.yaml
  argocd-app.yaml                 # ArgoCD Application pointing here

objects/                         # Reference manifests (not deployed)
  DaemonSet/, Deployment/, Job/, Network/,
  Pod/, ReplicaSet/, StatefulSet/

create-kubernetes-in-AWS/        # Reference scripts (not deployed)
  docker-compose.yaml
  Onprem-Kubernetes-Installation-Master-Node.md
  Onprem-Kubernetes-Installation-Worker-Node.md
  Single_Node_Cluster.sh
```

## First-time setup

1. **Apply ClusterIssuer** (must come before any ingress that uses it):
   ```sh
   kubectl apply -f bank-project/cluster-issuer.yaml
   ```
2. **Apply ArgoCD namespace + ingress** (after nginx-ingress and cert-manager
   are installed by Terraform):
   ```sh
   kubectl apply -f bank-project/argocd-namespace.yaml
   kubectl apply -f bank-project/ingress-argocd.yaml
   ```
3. **Populate DB Secret** from Terraform outputs:
   ```sh
   RDS_HOST=$(terraform -chdir=../stanley-bank-aws output -raw rds_endpoint)
   kubectl -n default create secret generic db-secrets \
     --from-literal=username=stanleyadmin \
     --from-literal=password=$DB_PASSWORD \
     --from-literal=host=$RDS_HOST \
     --from-literal=port=5432 \
     --save-config --dry-run=client -o yaml | kubectl apply -f -
   ```
4. **Replace ACM cert ARN placeholders** in `frontend-ingress.yaml` and
   `backend-ingress.yaml`:
   ```sh
   ACM_ARN=$(terraform -chdir=../stanley-bank-aws output -raw acm_certificate_arn)
   sed -i "s|REPLACE_WITH_ACM_CERT_ARN|$ACM_ARN|g" \
     bank-project/frontend-ingress.yaml \
     bank-project/backend-ingress.yaml
   git commit -am "configure: ACM cert ARN" && git push
   ```
5. **Apply the ArgoCD Application** (one-time bootstrap):
   ```sh
   kubectl apply -f bank-project/argocd-app.yaml
   ```

## Image tag placeholders

`frontend-deployment.yaml` and `backend-deployment.yaml` ship with
`image: REPLACE_WITH_ECR_IMAGE` as a sentinel. The first real image tag is
written by the GitHub Actions workflow on the next push to `main` in the
respective app repo.

## Route53 alias records (after the first apply)

The ArgoCD NLB and the app/api ALBs are created asynchronously by the
ingress controllers and cannot be referenced from Terraform at apply
time. After the cluster is up and the ingresses exist, create the alias
records manually:

```sh
# Get the NLB DNS for the nginx ingress (ArgoCD lives behind this)
kubectl -n ingress-nginx get svc ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Get the ALB DNS for app/api (after the ingresses have a public address)
kubectl get ingress -A
# Look for stanley-bank-frontend-ingress and stanley-bank-backend-ingress.

# Look up the ALB's canonical hosted zone ID
aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?contains(LoadBalancerName, `k8s`)].[LoadBalancerName,CanonicalHostedZoneId,DNSName]' \
  --output table --region us-east-2
```

Then create alias records in Route53 pointing `argocd.`, `api.`, and
`app.` stanleybank.site to those DNS names. The Terraform
`route53_name_servers` output is still authoritative for the parent
`stanleybank.site` zone.
