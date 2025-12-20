rm redis.key redis.crt redis1.key redis1.crt redis2.key redis2.crt 

aws eks update-kubeconfig --name demo-eks-istio --region ap-southeast-2

kubectl delete secret redis1-credential -n istio-system
kubectl delete secret redis2-credential -n istio-system

openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout redis1.key \
  -out redis1.crt \
  -subj "/CN=redis1.demo.local" \
  -addext "subjectAltName=DNS:redis1.demo.local"

openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout redis2.key \
  -out redis2.crt \
  -subj "/CN=redis2.demo.local" \
  -addext "subjectAltName=DNS:redis2.demo.local"

kubectl create secret tls redis1-credential \
  -n istio-system \
  --key redis1.key \
  --cert redis1.crt

kubectl create secret tls redis2-credential \
  -n istio-system \
  --key redis2.key \
  --cert redis2.crt

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
# REDIS1 service
kubectl apply -f - <<'YAML'
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: redis1
    namespace: demo
  spec:
    replicas: 1
    selector:
      matchLabels: { app: redis1 }
    template:
      metadata:
        labels: { app: redis1 }
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
    name: redis1
    namespace: demo
  spec:
    selector: { app: redis1 }
    ports:
      - name: tcp-redis
        port: 6379
        targetPort: 6379
        protocol: TCP
YAML

# ---
kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: redis1
  namespace: demo
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 6379
      name: tls-redis
      protocol: TLS
    tls:
      mode: SIMPLE
      credentialName: redis1-credential
    hosts:
    - redis1.demo.local
YAML

#  ---
kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: redis1
  namespace: demo
spec:
  hosts:
  - redis1.demo.local
  gateways:
  - demo/redis1
  tcp:
  - match:
    - port: 6379
    route:
    - destination:
        host: redis1.demo.svc.cluster.local
        port:
          number: 6379
YAML

# ----------------
# REDIS2 service
kubectl apply -f - <<'YAML'
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: redis2
    namespace: demo
  spec:
    replicas: 1
    selector:
      matchLabels: { app: redis2 }
    template:
      metadata:
        labels: { app: redis2 }
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
    name: redis2
    namespace: demo
  spec:
    selector: { app: redis2 }
    ports:
      - name: tcp-redis
        port: 6379
        targetPort: 6379
        protocol: TCP
YAML

# ---
kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: redis2
  namespace: demo
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 6379
      name: tls-redis
      protocol: TLS
    tls:
      mode: SIMPLE
      credentialName: redis2-credential
    hosts:
    - redis2.demo.local
YAML

#  ---
kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: redis2
  namespace: demo
spec:
  hosts:
  - redis2.demo.local
  gateways:
  - demo/redis2
  tcp:
  - match:
    - port: 6379
    route:
    - destination:
        host: redis2.demo.svc.cluster.local
        port:
          number: 6379
YAML


INGRESS=$(kubectl -n istio-system get svc istio-ingressgateway  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo $INGRESS

redis-cli   --tls   --cacert ./redis1.crt   --sni redis1.demo.local   -h redis1.demo.local   -p 6379   
redis-cli   --tls   --cacert ./redis2.crt   --sni redis2.demo.local   -h redis2.demo.local   -p 6379   
redis-cli   --tls   --cacert ./redis1.crt   --sni redis1.demo.local   -h redis1.demo.local   -p 6379   


