
# Deploy-Infra: https://dev.azure.com/vvp-vvproj/vvproj/_build?definitionId=2

# This deploys a Kubernetes in Azure Cloud using Terraform.

#region Login Azure
  az login
  az account list
  az account show

  $env:SUBSCRIPTION_ID = "34e8edd7-0778-437c-87a8-77d284221066"; $env:SUBSCRIPTION_ID # Vasile Popovici - VS Prof Subscr
  az account set --subscription $env:SUBSCRIPTION_ID
  Connect-AzAccount -SubscriptionId $env:SUBSCRIPTION_ID # VvpVvproj
#endregion

#region Terraform
  ./deploy/scripts/Initialize-Vvpsoll-Infrastructure.ps1

  ./deploy/scripts/Invoke-Vvpsoll-TerraformDeployment.ps1 -ConfirmApply $false

  # Destroy everything
  # terraform -chdir=tf-azure destroy
#endregion

#region Build and Deploy apps

  ### MODELS. (!!!) Make sure you downloaded the _models files to ./_models/volume-data/
  $env:VITE_API_BASE_URL = "/video-upload-api"
  @(
    "../tpi-video-analysis-ui",
    "../tpi-upload-video-api",
    "../tpi-video-analysis-service/_models",
    "../vvproj-ml",
    "../tpi-video-analysis-lib",
    "../tpi-video-analysis-service"
  ) | ./deploy/scripts/Build-Vvpsoll-App.ps1 -ImageTag latest

  @(
    "../tpi-video-analysis-ui",
    "../tpi-upload-video-api",
    "../tpi-video-analysis-service"
  ) | ./deploy/scripts/Deploy-Vvpsoll-AppToKubernetes.ps1 -ImageTag latest

#endregion

#region Useful commands

  # Get the logs
  kubectl logs -n vvpsoll -l app=vvpsoll-ui --all-containers=true -f
  kubectl logs -n vvpsoll -l app=vvpsoll-api --all-containers=true -f
  kubectl logs -n vvpsoll -l app=vvpsoll-srv --all-containers=true -f
  # Get POD name
  $pod = $(kubectl get pods -n vvpsoll -l app=vvpsoll-ui -o jsonpath="{.items[*].metadata.name}")
  $pod = $(kubectl get pods -n vvpsoll -l app=vvpsoll-api -o jsonpath="{.items[*].metadata.name}")
  $pod = $(kubectl get pods -n vvpsoll -l app=vvpsoll-srv -o jsonpath="{.items[*].metadata.name}")
  kubectl exec -it $pod -n vvpsoll -- /bin/bash

  # Check Connection to Storage Account:
  $accessKey = (az storage account keys list --resource-group rg-vvpsoll-vvp-demo --account-name savvpsollvvpdemo --query "[0].value" --output tsv)
  $sas = $(az storage container generate-sas --account-name savvpsollvvpdemo --name vvpsoll-data --permissions lr --expiry 2025-12-31T23:59:00Z --account-key $accessKey --https-only --output tsv)

  curl -s "https://savvpsollvvpdemo.blob.core.windows.net/vvpsoll-data?restype=container&comp=list&${sas}"

  # Connect to AKS Cluster
  $RESOURCE_GROUP_NAME = "rg-vvpsoll-vvp-demo"
  $AKS_NAME = "aks-vvpsoll-vvp-demo"
  az aks get-credentials --resource-group $RESOURCE_GROUP_NAME --name $AKS_NAME --overwrite-existing
  kubelogin convert-kubeconfig -l azurecli
  kubectl get nodes
  kubectl get pods --all-namespaces

  kubectl get all
  kubectl get ingress
  kubectl get certificate
  kubectl describe certificate letsencrypt-prod-account-key
  kubectl delete certificate letsencrypt-prod-account-key
  kubectl get certificaterequest
  kubectl describe certificaterequest letsencrypt-prod-account-key-1
  kubectl delete certificaterequest letsencrypt-prod-account-key-1
  kubectl get challenge
  kubectl describe challenge letsencrypt-prod-account-key-1-1551243196-2221745336
  kubectl delete challenges --all
  kubectl get events --namespace vvpsoll
  kubectl get pods -l app=sample-webapp

  curl -I http://vvpsoll-vvp-demo.westeurope.cloudapp.azure.com/.well-known/acme-challenge/test

  curl "https://${env:AKS_INGRESS_FQDN}"
  curl "https://${env:AKS_INGRESS_FQDN}/healthcheck"

  kubectl describe pod sample-webapp-699f778656-tplvm
  kubectl exec sample-webapp-699f778656-tplvm -- bash

# Install Ingress Controler
  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
  helm repo update
  helm show values ingress-nginx/ingress-nginx > helm-ingress-nginx-values.yaml

# Set variable for ACR location to use for pulling images
$ACR_URL = terraform output -raw container_registry_login_server

# Use Helm to deploy an NGINX ingress controller
helm upgrade --install ingress-nginx ingress-nginx `
  --repo https://kubernetes.github.io/ingress-nginx `
  --namespace ingress-nginx `
  --create-namespace `
  --set controller.service.loadBalancerIP=52.174.241.61 `
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-resource-group"="rg-vvpsoll-vvp-demo" `
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-dns-label-name"="vvpsoll-vvp-demo"

# Break the lease for tfstate file
  az storage blob show --account-name "satfbackendaivisiondemo" --container-name "tfbackend-aivision-demo" --name "terraform.tfstate" --auth-mode login --query "properties.lease"
  az storage blob lease break --container-name "tfbackend-aivision-demo" --account-name "satfbackendaivisiondemo" --blob-name "terraform.tfstate" --auth-mode login

# Remove lock file
  az storage blob list --account-name "satfbackendaivisiondemo" --container-name "tfbackend-aivision-demo" --auth-mode login --query "[?name=='terraform.tfstate'].name"
  az storage blob delete --account-name "satfbackendaivisiondemo" --container-name "tfbackend-aivision-demo" --name "terraform.tfstate.lock.info" --auth-mode login

#endregion
