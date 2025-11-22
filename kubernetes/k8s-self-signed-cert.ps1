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
helm upgrade --hide-notes `
  --install "ingress-nginx" "ingress-nginx/ingress-nginx" `
  --namespace "ingress-nginx" --create-namespace `
  --set controller.replicaCount=1

# Deploy an app
kubectl create deployment app1 --image=nginx:latest --dry-run=client -o yaml | kubectl apply -f -
kubectl expose deployment app1 --port=80 --target-port=80 --type=ClusterIP --dry-run=client -o yaml | kubectl apply -f -

# Deploy Ingress for the app with TLS in root (/)
kubectl create ingress app1 --class=nginx --rule="${aDomain}/=app1:80,tls=self-signed-tls-${aDomain}" --dry-run=client -o yaml | kubectl apply -f -

curl -iv "https://${aDomain}/"

# Update Ingress for the app with TLS in path /app1 and annotations for regex.
@"
  apiVersion: networking.k8s.io/v1
  kind: Ingress
  metadata:
    name: app1
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
            - path: /app1(/|$)(.*)
              pathType: ImplementationSpecific
              backend:
                service:
                  name: app1
                  port:
                    number: 80
"@ | kubectl apply -f -

curl -iv "https://${aDomain}/app1"

# Cleanup
kubectl delete deployment app1 --ignore-not-found
kubectl delete service app1 --ignore-not-found
kubectl delete ingress app1 --ignore-not-found
