rm cass*.key cass*.crt

openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout cass1.key \
  -out cass1.crt \
  -subj "/CN=cass1.demo.local" \
  -addext "subjectAltName=DNS:cass1.demo.local"

openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout cass2.key \
  -out cass2.crt \
  -subj "/CN=cass2.demo.local" \
  -addext "subjectAltName=DNS:cass2.demo.local"

kubectl -n istio-system delete secret cass1-credential cass2-credential --ignore-not-found

kubectl create secret tls cass1-credential -n istio-system --key cass1.key --cert cass1.crt
kubectl create secret tls cass2-credential -n istio-system --key cass2.key --cert cass2.crt


# ---

kubectl create namespace demo
kubectl label ns demo istio-injection=enabled --overwrite=true

# ----------------------------
# CASS1 (single-node demo)
# ----------------------------

kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: cass1-hl
  namespace: demo
spec:
  clusterIP: None
  selector:
    app: cass1
  ports:
    - name: cql
      port: 9042
      targetPort: 9042
    - name: intra
      port: 7000
      targetPort: 7000
    - name: intra-tls
      port: 7001
      targetPort: 7001
YAML

# ---

kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: cass1
  namespace: demo
spec:
  selector:
    app: cass1
  ports:
    - name: cql
      port: 9042
      targetPort: 9042
      protocol: TCP
YAML

# ---

kubectl apply -f - <<'YAML'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: cass1
  namespace: demo
  annotations:
    sidecar.istio.io/proxyCPU: "10m"
    sidecar.istio.io/proxyCPULimit: "100m"
    sidecar.istio.io/proxyMemory: "64Mi"
    sidecar.istio.io/proxyMemoryLimit: "128Mi"
spec:
  serviceName: cass1-hl
  replicas: 1
  selector:
    matchLabels:
      app: cass1
  template:
    metadata:
      labels:
        app: cass1
    spec:
      securityContext:
        fsGroup: 999
      terminationGracePeriodSeconds: 120
      containers:
        - name: cassandra
          image: cassandra:4.1
          ports:
            - containerPort: 9042
              name: cql
            - containerPort: 7000
              name: intra
            - containerPort: 7001
              name: intra-tls
          env:
            - name: CASSANDRA_CLUSTER_NAME
              value: "cass1-cluster"
            - name: CASSANDRA_SEEDS
              value: "cass1-0.cass1-hl.demo.svc.cluster.local"
            - name: CASSANDRA_DC
              value: "dc1"
            - name: CASSANDRA_RACK
              value: "rack1"
            # small-ish heap for demo; adjust as needed
            - name: MAX_HEAP_SIZE
              value: "256M"
            - name: HEAP_NEWSIZE
              value: "128M"
          readinessProbe:
            tcpSocket:
              port: 9042
            initialDelaySeconds: 45
            periodSeconds: 10
          resources:
            requests:
              cpu: "100m"
              memory: "512Mi"
            limits:
              memory: "1Gi"
          volumeMounts:
            - name: cass1-data
              mountPath: /var/lib/cassandra
      volumes:
        - name: cass1-data
          emptyDir: {}
YAML

# ---

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: cass1
  namespace: demo
spec:
  selector:
    istio: ingressgateway
  servers:
    - port:
        number: 443
        name: tls-cql-cass1
        protocol: TLS
      tls:
        mode: SIMPLE
        credentialName: cass1-credential
      hosts:
        - cass1.demo.local
YAML

# ---

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: cass1
  namespace: demo
spec:
  hosts:
    - cass1.demo.local
  gateways:
    - demo/cass1
  tcp:
    - match:
        - port: 443
      route:
        - destination:
            host: cass1.demo.svc.cluster.local
            port:
              number: 9042
YAML

# ----------------------------
# CASS2 (single-node demo)
# ----------------------------

kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: cass2-hl
  namespace: demo
  annotations:
    sidecar.istio.io/proxyCPU: "10m"
    sidecar.istio.io/proxyCPULimit: "100m"
    sidecar.istio.io/proxyMemory: "64Mi"
    sidecar.istio.io/proxyMemoryLimit: "128Mi"
spec:
  clusterIP: None
  selector:
    app: cass2
  ports:
    - name: cql
      port: 9042
      targetPort: 9042
    - name: intra
      port: 7000
      targetPort: 7000
    - name: intra-tls
      port: 7001
      targetPort: 7001
YAML

# ---

kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: cass2
  namespace: demo
spec:
  selector:
    app: cass2
  ports:
    - name: cql
      port: 9042
      targetPort: 9042
      protocol: TCP
YAML

# ---

kubectl apply -f - <<'YAML'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: cass2
  namespace: demo
spec:
  serviceName: cass2-hl
  replicas: 1
  selector:
    matchLabels:
      app: cass2
  template:
    metadata:
      labels:
        app: cass2
    spec:
      securityContext:
        fsGroup: 999
      terminationGracePeriodSeconds: 120
      containers:
        - name: cassandra
          image: cassandra:4.1
          ports:
            - containerPort: 9042
              name: cql
            - containerPort: 7000
              name: intra
            - containerPort: 7001
              name: intra-tls
          env:
            - name: CASSANDRA_CLUSTER_NAME
              value: "cass2-cluster"
            - name: CASSANDRA_SEEDS
              value: "cass2-0.cass2-hl.demo.svc.cluster.local"
            - name: CASSANDRA_DC
              value: "dc1"
            - name: CASSANDRA_RACK
              value: "rack1"
            - name: MAX_HEAP_SIZE
              value: "256M"
            - name: HEAP_NEWSIZE
              value: "128M"
          readinessProbe:
            tcpSocket:
              port: 9042
            initialDelaySeconds: 45
            periodSeconds: 10
          resources:
            requests:
              cpu: "100m"
              memory: "512Mi"
            limits:
              memory: "1Gi"
          volumeMounts:
            - name: cass2-data
              mountPath: /var/lib/cassandra
      volumes:
        - name: cass2-data
          emptyDir: {}
YAML

# ---

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: cass2
  namespace: demo
spec:
  selector:
    istio: ingressgateway
  servers:
    - port:
        number: 443
        name: tls-cql-cass2
        protocol: TLS
      tls:
        mode: SIMPLE
        credentialName: cass2-credential
      hosts:
        - cass2.demo.local
YAML
# # ---
kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: cass2
  namespace: demo
spec:
  hosts:
    - cass2.demo.local
  gateways:
    - demo/cass2
  tcp:
    - match:
        - port: 443
      route:
        - destination:
            host: cass2.demo.svc.cluster.local
            port:
              number: 9042
YAML

INGRESS=$(kubectl -n istio-system get svc istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "$INGRESS"
nslookup "$INGRESS"

stunnel stunnel-cass1.conf &
cqlsh 127.0.0.1 19043
# cqlsh cass1.demo.local 443 --ssl --cqlshrc ./cqlshrc-cass1
# cqlsh cass2.demo.local 443 --ssl --cqlshrc ./cqlshrc-cass2


# # Should succeed (shows cert CN/SAN = cass1.demo.local)
# openssl s_client -connect cass1.demo.local:443 -servername cass1.demo.local -CAfile cass1.crt -brief

# openssl s_client   -connect redis1.demo.local:443   -servername redis1.demo.local   -CAfile redis1.crt


# # If THIS fails / resets, your client path is missing SNI (or gateway/secret isn't right)
# openssl s_client -connect cass1.demo.local:443 -CAfile cass1.crt -brief


# kubectl -n istio-system logs deploy/istio-ingressgateway -c istio-proxy --tail=200 | egrep -i "filter.chain|filter_chain|no matching"
