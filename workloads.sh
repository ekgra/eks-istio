aws eks update-kubeconfig --name demo-eks-istio --region ap-southeast-2

# ----------------

kubectl create namespace demo
kubectl label ns demo istio-injection=enabled --overwrite=true
# (Optional but helpful if you ever flip mesh to STRICT)
kubectl apply -n demo -f - <<'YAML'
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: demo-permissive
spec:
  mtls:
    mode: PERMISSIVE
YAML


kubectl apply -n demo -f - <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pod-http
spec:
  replicas: 1
  selector:
    matchLabels: { app: pod-http }
  template:
    metadata:
      labels: { app: pod-http }
    spec:
      containers:
        - name: http-echo
          image: hashicorp/http-echo:0.2.3
          args: ["-text=hello-from-pod-http", "-listen=:8080"]
          ports: [{ containerPort: 8080 }]
---
apiVersion: v1
kind: Service
metadata:
  name: pod-http
spec:
  selector: { app: pod-http }
  ports:
    - name: http
      port: 8080
      targetPort: 8080
YAML

---

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: demo-gw
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

---

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: pod-http-vs
  namespace: demo
spec:
  hosts: ["*"]
  gateways: ["demo/demo-gw"]
  http:
    - match:
        - uri: { prefix: "/" }
      route:
        - destination:
            host: pod-http.demo.svc.cluster.local
            port: { number: 8080 }
YAML

---

INGRESS=$(kubectl -n istio-system get svc istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl -s http://$INGRESS/
# -> hello-from-pod-http


---

kubectl apply -f - <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
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

---

kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: redis
spec:
  selector: { app: redis }
  ports:
    - name: redis
      port: 6379
      targetPort: 6379
      protocol: TCP
YAML

---

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: demo-gw-tcp
  namespace: demo
spec:
  selector:
    istio: ingressgateway
  servers:
    - port:
        number: 9092
        name: tcp-redis
        protocol: TCP
      hosts:
        - "*"
YAML

---

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: redis-tcp-vs
  namespace: demo
spec:
  gateways: ["demo/demo-gw-tcp"]
  hosts: ["*"]
  tcp:
    - match:
        - port: 9092
      route:
        - destination:
            host: redis.demo.svc.cluster.local
            port: { number: 6379 }
YAML

---

INGRESS=$(kubectl -n istio-system get svc istio-ingressgateway  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo $INGRESS

# If you have redis-cli locally:
redis-cli -h "$INGRESS" -p 9092 PING
# -> PONG
