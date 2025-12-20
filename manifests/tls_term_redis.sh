rm redis.key redis.crt 

aws eks update-kubeconfig --name demo-eks-istio --region ap-southeast-2

kubectl delete secret redis-credential -n istio-system

openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout redis.key \
  -out redis.crt \
  -subj "/CN=redis.demo.local" \
  -addext "subjectAltName=DNS:redis.demo.local"

kubectl create secret tls redis-credential \
  -n istio-system \
  --key redis.key \
  --cert redis.crt

# ----------------

kubectl create namespace demo
kubectl label ns demo istio-injection=enabled --overwrite=true

kubectl apply -f - <<'YAML'
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: default
  namespace: istio-system
spec:
  mtls:
    mode: STRICT
YAML


# ----------------
# REDIS service
kubectl apply -f - <<'YAML'
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: redis
    namespace: demo
  spec:
    replicas: 1
    selector:
      matchLabels: { app: redis }
    template:
      metadata:
        labels: { app: redis }
      spec:
        containers:
          - name: redis
            image: redis:7-alpine
            ports:
              - containerPort: 6379
            resources:
              requests: { cpu: "50m", memory: "64Mi" }
              limits:   { memory: "128Mi" }
YAML

#  ---

kubectl apply -f - <<'YAML'
  apiVersion: v1
  kind: Service
  metadata:
    name: redis
    namespace: demo
  spec:
    selector: { app: redis }
    ports:
      - name: redis
        port: 6379
        targetPort: 6379
        protocol: TCP
YAML

# ---

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: http
  namespace: demo
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 443
      name: https
      protocol: HTTPS
    tls:
      mode: SIMPLE
      credentialName: http-credential
    hosts:
    - http.demo.local
YAML

#  ---

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: http
  namespace: demo
spec:
  hosts:
  - http.demo.local
  gateways:
  - demo/http
  http:
  - match:
    - uri:
        prefix: /
    route:
    - destination:
        host: http.demo.svc.cluster.local
        port:
          number: 8080
YAML


INGRESS=$(kubectl -n istio-system get svc istio-ingressgateway  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo $INGRESS

curl -v \
  --cacert /Users/outlander/workDir/study/18k8s/09EKS-istio/http.crt \
  --connect-to http.demo.local:443:$INGRESS:443 \
  https://http.demo.local/

