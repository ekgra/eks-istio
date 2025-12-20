rm -rf *.crt *.key *.csr *.ext *.srl

aws eks update-kubeconfig --name demo-eks-istio --region ap-southeast-2

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
# HTTP service
kubectl apply -f - <<'YAML'
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: http
      namespace: demo
    spec:
      replicas: 1
      selector:
        matchLabels: { app: http }
      template:
        metadata:
          labels: { app: http }
        spec:
          containers:
            - name: http-echo
              image: hashicorp/http-echo:0.2.3
              args: ["-text=hello-from-pod-http", "-listen=:8080"]
              ports: [{ containerPort: 8080 }]
YAML

# ---

kubectl apply -f - <<'YAML'
  apiVersion: v1
  kind: Service
  metadata:
    name: http
    namespace: demo
  spec:
    selector: { app: http }
    ports:
      - name: http
        port: 8080
        targetPort: 8080
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
          number: 80
          name: http
          protocol: HTTP
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
    gateways: ["demo/http"]
    http:
      - match:
          - uri: { prefix: "/" }
        route:
          - destination:
              host: http.demo.svc.cluster.local
              port: { number: 8080 }
YAML

# ----------------
# Redis

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

#  ---

kubectl apply -f - <<'YAML'
  apiVersion: networking.istio.io/v1beta1
  kind: Gateway
  metadata:
    name: redis
    namespace: demo
  spec:
    selector:
      istio: ingressgateway
    servers:
      - port:
          number: 6379
          name: tcp-redis
          protocol: TCP
        hosts:
          - "*"
YAML

#  ---

kubectl apply -f - <<'YAML'
  apiVersion: networking.istio.io/v1beta1
  kind: VirtualService
  metadata:
    name: redis
    namespace: demo
  spec:
    gateways: ["demo/redis"]
    hosts: ["*"]
    tcp:
      - match:
          - port: 6379
        route:
          - destination:
              host: redis.demo.svc.cluster.local
              port: { number: 6379 }
YAML

#  ---

INGRESS=$(kubectl -n istio-system get svc istio-ingressgateway  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo $INGRESS

nslookup $INGRESS

curl -v \
  --connect-to http.demo.local:80:$INGRESS:80 \
  http://http.demo.local/

redis-cli -h "$INGRESS" -p 6379 PING

redis-cli -h redis.demo.local -p 6379 PING