# Kubernetes Ingress — HTTP to HTTPS with Self-Signed Certificates, https://medium.com/@muppedaanvesh/%EF%B8%8F-kubernetes-ingress-transitioning-to-https-with-self-signed-certificates-0c7ab0231e76

Set-Location -Path C:\Repos\EnRepos\Argo-CD-App-And-Ingress

# Update DNS mapping in hosts file
$aIp, $aDomain, $hostsFile = "127.0.0.2", "rancher.localhost", "C:\Windows\System32\drivers\etc\hosts"
if (Select-String -Pattern $aDomain -Path $hostsFile) {
  Write-Host "A Record '$aIp $aDomain' already exists in $hostsFile."
} else {
  Add-Content -Path $hostsFile -Value "$aIp $aDomain" -Verbose
}
Select-String -Pattern "^#.*|^$" -NotMatch -Path $hostsFile | Select-String -Pattern $aDomain -Raw

# Generate the *.key and *.crt files
docker run --rm -it -v "${PWD}/:/certs/" alpine/openssl `
  req -verbose -x509 -days 365 `
  -sha384 -nodes `
  -newkey ec -pkeyopt ec_paramgen_curve:P-384 `
  -keyout "/certs/${aDomain}.key" -out "/certs/${aDomain}.crt" `
  -subj "/CN=${aDomain}" `
  -addext "subjectAltName=DNS:${aDomain},DNS:*.${aDomain}" `
  -addext "basicConstraints=CA:FALSE" `
  -addext "keyUsage=critical,digitalSignature" `
  -addext "extendedKeyUsage=serverAuth"

# Upload the TLS secret into Kubernetes
kubectl create secret tls "self-signed-tls-${aDomain}" --key "${aDomain}.key" --cert "${aDomain}.crt" --dry-run=client -o yaml | kubectl apply -f -

# Import the self-signed certificate into Windows Trusted Root Certification Authorities
Import-Certificate -FilePath "${aDomain}.crt" -CertStoreLocation "Cert:\CurrentUser\Root\" -Verbose

# Install Nginx Ingress Controller
helm repo add "ingress-nginx" "https://kubernetes.github.io/ingress-nginx"
helm repo update
helm search repo ingress-nginx
helm upgrade --install "ingress-nginx" "ingress-nginx/ingress-nginx" --version 4.14.0 `
  --namespace "ingress-nginx" --create-namespace --hide-notes `
  --set controller.replicaCount=1

# Deploy an app
kubectl delete deployment blog-app --ignore-not-found
kubectl delete service blog-app --ignore-not-found

kubectl create deployment blog-app --image=nginx:latest --dry-run=client -o yaml | kubectl apply -f -
kubectl expose deployment blog-app --port=80 --target-port=80 --type=ClusterIP --dry-run=client -o yaml | kubectl apply -f -

kubectl create ingress blog-ingress --class=nginx --rule="${aDomain}/=blog-app:80,tls=self-signed-tls-${aDomain}" --dry-run=client -o yaml | kubectl apply -f -
curl -ivv "https://${aDomain}/"

@"
  apiVersion: networking.k8s.io/v1
  kind: Ingress
  metadata:
    name: blog-ingress
    annotations:
      nginx.ingress.kubernetes.io/use-regex: "true"
      nginx.ingress.kubernetes.io/rewrite-target: /$2
      # nginx.ingress.kubernetes.io/whitelist-source-range: "<COMMA SEPARATED ALLOWED IPS"
  spec:
    ingressClassName: nginx
    tls:
      - secretName: self-signed-tls-${aDomain}
        hosts:
          - ${aDomain}
    rules:
      - host: ${aDomain}
        http:
          paths:
            - path: /blog(/|$)(.*)
              pathType: ImplementationSpecific
              backend:
                service:
                  name: blog-app
                  port:
                    number: 80
"@ | kubectl apply -f -

curl -iv "https://${aDomain}/blog"
