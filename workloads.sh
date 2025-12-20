aws eks update-kubeconfig --name demo-eks-istio --region ap-southeast-2

# ---

kubectl create namespace demo
kubectl label ns demo istio-injection=enabled --overwrite=true
# (Optional but helpful if you ever flip mesh to STRICT)
kubectl apply -n demo -f - <<'YAML'
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: demo
spec:
  mtls:
    mode: STRICT
YAML


kubectl apply -n demo -f - <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: http
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
# ---
apiVersion: v1
kind: Service
metadata:
  name: http
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
        - "*"
YAML

# ---

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: http
  namespace: demo
spec:
  hosts: ["*"]
  gateways: ["demo/http"]
  http:
    - match:
        - uri: { prefix: "/" }
      route:
        - destination:
            host: http.demo.svc.cluster.local
            port: { number: 8080 }
YAML

# ---

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

# ---

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

# ---

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

# ---

INGRESS=$(kubectl -n istio-system get svc istio-ingressgateway  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo $INGRESS

curl -s http://$INGRESS
curl -v \
  --connect-to http.demo.local:80:$INGRESS:80 \
  http://http.demo.local/

# If you have redis-cli locally:
redis-cli -h "$INGRESS" -p 6379 PING
# -> PONG
