rm kafka*.key kafka*.crt client-ssl.properties kafka-truststore.jks

aws eks update-kubeconfig --name demo-eks-istio --region ap-southeast-2

openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout kafka.key \
  -out kafka.crt \
  -subj "/CN=cp-kafka.demo.local" \
  -addext "subjectAltName=DNS:cp-kafka.demo.local"

kubectl -n istio-system delete secret kafka-credential --ignore-not-found
kubectl create secret tls kafka-credential -n istio-system --key kafka.key --cert kafka.crt


kubectl create namespace demo
kubectl label ns demo istio-injection=enabled --overwrite=true

# -------------------------
# Zookeeper (single node)
# -------------------------
kubectl apply -f - <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: zk
  namespace: demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: zk
  template:
    metadata:
      labels:
        app: zk
    spec:
      containers:
        - name: zookeeper
          image: confluentinc/cp-zookeeper:latest
          ports:
            - containerPort: 2181
              name: client
          env:
            - name: ZOOKEEPER_CLIENT_PORT
              value: "2181"
            - name: ZOOKEEPER_TICK_TIME
              value: "2000"
          resources:
            requests:
              cpu: "100m"
              memory: "256Mi"
            limits:
              memory: "512Mi"
YAML

# ---

kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: zk
  namespace: demo
spec:
  selector:
    app: zk
  ports:
    - name: tcp-zk
      port: 2181
      targetPort: 2181
      protocol: TCP
YAML


# -------------------------
# cp-kafka (single broker)
# INTERNAL: PLAINTEXT 9092 (in-cluster)
# EXTERNAL: PLAINTEXT 443  (traffic coming from Istio after TLS termination)
# -------------------------

kubectl apply -f - <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cp-kafka
  namespace: demo
spec:
  replicas: 1
  selector:
    matchLabels: { app: cp-kafka }
  template:
    metadata:
      labels: { app: cp-kafka }
    spec:
      containers:
        - name: kafka
          image: confluentinc/cp-kafka:7.9.1
          ports:
            - containerPort: 9092
              name: internal
            - containerPort: 443
              name: external
          env:
            - name: KAFKA_BROKER_ID
              value: "1"
            - name: KAFKA_ZOOKEEPER_CONNECT
              value: "zk.demo.svc.cluster.local:2181"

            # Two listeners in the pod
            - name: KAFKA_LISTENERS
              value: "INTERNAL://0.0.0.0:9092,EXTERNAL://0.0.0.0:443"

            # Advertise different endpoints for different client types:
            # - pods: cp-kafka.demo.svc:9092
            # - external: cp-kafka.demo.local:443 (via Istio ingress)
            - name: KAFKA_ADVERTISED_LISTENERS
              value: "INTERNAL://cp-kafka.demo.svc.cluster.local:9092,EXTERNAL://cp-kafka.demo.local:443"

            - name: KAFKA_LISTENER_SECURITY_PROTOCOL_MAP
              value: "INTERNAL:PLAINTEXT,EXTERNAL:PLAINTEXT"

            # Inter-broker traffic stays internal
            - name: KAFKA_INTER_BROKER_LISTENER_NAME
              value: "INTERNAL"

            # Single broker topic defaults
            - name: KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR
              value: "1"
            - name: KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR
              value: "1"
            - name: KAFKA_TRANSACTION_STATE_LOG_MIN_ISR
              value: "1"
            - name: KAFKA_MIN_INSYNC_REPLICAS
              value: "1"

            # Keep heap small for demo clusters
            - name: KAFKA_HEAP_OPTS
              value: "-Xms256m -Xmx256m"
          resources:
            requests: { cpu: "200m", memory: "512Mi" }
            limits:   { memory: "1Gi" }
YAML

# ---

kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: cp-kafka
  namespace: demo
spec:
  selector:
    app: cp-kafka
  ports:
    - name: tcp-internal
      port: 9092
      targetPort: 9092
      protocol: TCP
    - name: tcp-external
      port: 443
      targetPort: 443
      protocol: TCP
YAML

# -------------------------
# Istio TLS termination + TCP route to Kafka plaintext
# -------------------------

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: cp-kafka
  namespace: demo
spec:
  selector:
    istio: ingressgateway
  servers:
    - port:
        number: 443
        name: tls-kafka
        protocol: TLS
      tls:
        mode: SIMPLE
        credentialName: kafka-credential   # secret in istio-system
      hosts:
        - cp-kafka.demo.local
YAML

# ---

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: cp-kafka
  namespace: demo
spec:
  hosts:
    - cp-kafka.demo.local
  gateways:
    - demo/cp-kafka
  tcp:
    - match:
        - port: 443
      route:
        - destination:
            host: cp-kafka.demo.svc.cluster.local
            port:
              number: 443
YAML


INGRESS=$(kubectl -n istio-system get svc istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "$INGRESS"
nslookup "$INGRESS"



# openssl s_client -connect cp-kafka.demo.local:443 -servername cp-kafka.demo.local -CAfile kafka.crt -brief



keytool -importcert -alias cp-kafka-ca \
  -file kafka.crt \
  -keystore kafka-truststore.jks \
  -storepass changeit -noprompt

cat <<'EOF' | tee client-ssl.properties
security.protocol=SSL
ssl.truststore.location=/Users/outlander/workDir/study/18k8s/09EKS-istio/kafka-truststore.jks
ssl.truststore.password=changeit
EOF



kafka-topics \
  --bootstrap-server  cp-kafka.demo.local:443 \
  --create \
  --topic test-topic \
  --partitions 1 \
  --replication-factor 1 \
  --command-config client-ssl.properties 



kafka-topics --bootstrap-server cp-kafka.demo.local:443 \
  --command-config client-ssl.properties \
  --list
