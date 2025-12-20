# ======== 1. Generate CA =========
# 1. Root CA
cd /Users/outlander/workDir/study/18k8s/09EKS-istio

openssl genrsa -out ca.key 4096

openssl req -x509 -new -nodes \
  -key ca.key \
  -sha256 -days 365 \
  -subj "/CN=demo-redis-ca" \
  -out ca.crt

# ======== 2. Generate redis server certs signed by CA  =========

# ======  2.1 REDIS 1 ============

openssl genrsa -out redis1-server.key 2048

openssl req -new \
  -key redis1-server.key \
  -out redis1-server.csr \
  -subj "/CN=redis1.demo.local"

cat > redis1-server.ext <<EOF
subjectAltName = DNS:redis1.demo.local
extendedKeyUsage = serverAuth
EOF

openssl x509 -req \
  -in redis1-server.csr \
  -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out redis1-server.crt \
  -days 365 -sha256 \
  -extfile redis1-server.ext

aws eks update-kubeconfig --name demo-eks-istio --region ap-southeast-2


kubectl create namespace demo || true
kubectl label ns demo istio-injection=enabled --overwrite=true

kubectl create secret generic redis1-tls \
  -n demo \
  --from-file=ca.crt=ca.crt \
  --from-file=tls.crt=redis1-server.crt \
  --from-file=tls.key=redis1-server.key



kubectl apply -f - <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis1
  namespace: demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis1
  template:
    metadata:
      labels:
        app: redis1
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        command: ["redis-server"]
        args:
          # Listen only on TLS
          - "--tls-port"
          - "6379"
          - "--port"
          - "0"

          # TLS server-side config
          - "--tls-cert-file"
          - "/etc/redis/tls/tls.crt"
          - "--tls-key-file"
          - "/etc/redis/tls/tls.key"
          - "--tls-ca-cert-file"
          - "/etc/redis/tls/ca.crt"

          # For server-only TLS:
          - "--tls-auth-clients"
          - "no"

          # If you want Redis mTLS, change to:
          # - "--tls-auth-clients"
          # - "yes"

        ports:
        - containerPort: 6379
          name: redis-tls
        volumeMounts:
        - name: redis-tls
          mountPath: /etc/redis/tls
          readOnly: true
      volumes:
      - name: redis-tls
        secret:
          secretName: redis1-tls
YAML



kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: redis1
  namespace: demo
spec:
  selector:
    app: redis1
  ports:
  - name: redis-tls
    port: 6379
    targetPort: 6379
    protocol: TCP
YAML


kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: redis1
  namespace: demo
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 9092
      name: tls-redis
      protocol: TLS
    tls:
      mode: PASSTHROUGH
    hosts:
    - redis1.demo.local
YAML



kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: redis1
  namespace: demo
spec:
  hosts:
  - redis1.demo.local
  gateways:
  - demo/redis1
  tls:
  - match:
    - port: 9092
      sniHosts:
      - redis1.demo.local
    route:
    - destination:
        host: redis1.demo.svc.cluster.local
        port:
          number: 6379
YAML

 


# ======  2.2 REDIS 2 ============

openssl genrsa -out redis2-server.key 2048

openssl req -new \
  -key redis2-server.key \
  -out redis2-server.csr \
  -subj "/CN=redis2.demo.local"

cat > redis2-server.ext <<EOF
subjectAltName = DNS:redis2.demo.local
extendedKeyUsage = serverAuth
EOF

openssl x509 -req \
  -in redis2-server.csr \
  -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out redis2-server.crt \
  -days 365 -sha256 \
  -extfile redis2-server.ext

kubectl create secret generic redis2-tls \
  -n demo \
  --from-file=ca.crt=ca.crt \
  --from-file=tls.crt=redis2-server.crt \
  --from-file=tls.key=redis2-server.key


kubectl apply -f - <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis2
  namespace: demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis2
  template:
    metadata:
      labels:
        app: redis2
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        command: ["redis-server"]
        args:
          # Listen only on TLS
          - "--tls-port"
          - "6379"
          - "--port"
          - "0"

          # TLS server-side config
          - "--tls-cert-file"
          - "/etc/redis/tls/tls.crt"
          - "--tls-key-file"
          - "/etc/redis/tls/tls.key"
          - "--tls-ca-cert-file"
          - "/etc/redis/tls/ca.crt"

          # For server-only TLS:
          - "--tls-auth-clients"
          - "no"

          # If you want Redis mTLS, change to:
          # - "--tls-auth-clients"
          # - "yes"

        ports:
        - containerPort: 6379
          name: redis-tls
        volumeMounts:
        - name: redis-tls
          mountPath: /etc/redis/tls
          readOnly: true
      volumes:
      - name: redis-tls
        secret:
          secretName: redis2-tls
YAML

kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: redis2
  namespace: demo
spec:
  selector:
    app: redis2
  ports:
  - name: redis-tls
    port: 6379
    targetPort: 6379
    protocol: TCP
YAML

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: redis2
  namespace: demo
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 9092
      name: tls-redis
      protocol: TLS
    tls:
      mode: PASSTHROUGH
    hosts:
    - redis2.demo.local
YAML

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: redis2
  namespace: demo
spec:
  hosts:
  - redis2.demo.local
  gateways:
  - demo/redis2
  tls:
  - match:
    - port: 9092
      sniHosts:
      - redis2.demo.local
    route:
    - destination:
        host: redis2.demo.svc.cluster.local
        port:
          number: 6379
YAML


# ======  3. Connect ============



redis-cli   --tls   --cacert ./ca.crt   --sni redis1.demo.local   -h redis1.demo.local   -p 9092   
redis-cli   --tls   --cacert ./ca.crt   --sni redis2.demo.local   -h redis2.demo.local   -p 9092   
redis-cli   --tls   --cacert ./ca.crt   --sni redis1.demo.local   -h redis1.demo.local   -p 9092   



