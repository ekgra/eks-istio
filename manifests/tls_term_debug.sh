rm svc*.key 

aws eks update-kubeconfig --name demo-eks-istio --region ap-southeast-2

kubectl delete secret svc1-credential -n istio-system
kubectl delete secret svc2-credential -n istio-system

openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout svc1.key \
  -out svc1.crt \
  -subj "/CN=svc1.demo.local" \
  -addext "subjectAltName=DNS:svc1.demo.local,DNS:debug-svc1.demo.local"

openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout svc2.key \
  -out svc2.crt \
  -subj "/CN=svc2.demo.local" \
  -addext "subjectAltName=DNS:svc2.demo.local,DNS:debug-svc2.demo.local"




kubectl create secret tls svc1-credential \
  -n istio-system \
  --key svc1.key \
  --cert svc1.crt

kubectl create secret tls svc2-credential \
  -n istio-system \
  --key svc2.key \
  --cert svc2.crt

# ----------------

kubectl create namespace demo
kubectl label ns demo istio-injection=enabled --overwrite=true

# ----------------
# SVC1

kubectl apply -f - <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: svc1
  namespace: demo
  labels:
    app: svc1
spec:
  replicas: 1
  selector:
    matchLabels:
      app: svc1
  template:
    metadata:
      labels:
        app: svc1
    spec:
      containers:
        - name: demodebug
          image: ekgra/demodebug:0.0.1
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 8080
            - name: jdwp
              containerPort: 5005
          env:
            # Normal mode: DEBUG=false (default). Debug chahiye to true kar dena.
            - name: DEBUG
              value: "true"
            # Optional: startup pe wait chahiye to y
            - name: DEBUG_SUSPEND
              value: "n"
          readinessProbe:
            httpGet:
              path: /actuator/health/readiness
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /actuator/health/liveness
              port: 8080
            initialDelaySeconds: 20
            periodSeconds: 10
YAML

# ---

kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: svc1
  namespace: demo
spec:
  type: ClusterIP
  selector:
    app: svc1
  ports:
    - name: http
      port: 8080
      targetPort: 8080
    - name: jdwp
      port: 5005
      targetPort: 5005
YAML

#  ---

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: svc1
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
      credentialName: svc1-credential
    hosts:
    - svc1.demo.local
  - port:
      number: 5005
      name: tls-jdwp
      protocol: TLS
    tls:
      mode: SIMPLE
      credentialName: svc1-credential
    hosts:
    - svc1.demo.local
YAML

#  ---

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: svc1
  namespace: demo
spec:
  hosts:
  - svc1.demo.local
  gateways:
  - demo/svc1
  http:
  - match:
    - uri:
        prefix: /
    route:
    - destination:
        host: svc1.demo.svc.cluster.local
        port:
          number: 8080
  tcp:
    - match:
        - port: 5005
      route:
        - destination:
            host: svc1.demo.svc.cluster.local
            port:
              number: 5005
YAML

# ----------------
# SVC2

kubectl apply -f - <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: svc2
  namespace: demo
  labels:
    app: svc2
spec:
  replicas: 1
  selector:
    matchLabels:
      app: svc2
  template:
    metadata:
      labels:
        app: svc2
    spec:
      containers:
        - name: demodebug
          image: ekgra/demodebug:0.0.1
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 8080
            - name: jdwp
              containerPort: 5005
          env:
            # Normal mode: DEBUG=false (default). Debug chahiye to true kar dena.
            - name: DEBUG
              value: "true"
            # Optional: startup pe wait chahiye to y
            - name: DEBUG_SUSPEND
              value: "n"
          readinessProbe:
            httpGet:
              path: /actuator/health/readiness
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /actuator/health/liveness
              port: 8080
            initialDelaySeconds: 20
            periodSeconds: 10
YAML

# ---

kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: svc2
  namespace: demo
spec:
  type: ClusterIP
  selector:
    app: svc2
  ports:
    - name: http
      port: 8080
      targetPort: 8080
    - name: jdwp
      port: 5005
      targetPort: 5005
YAML

#  ---

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: svc2
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
      credentialName: svc2-credential
    hosts:
    - svc2.demo.local
  - port:
      number: 5005
      name: tls-jdwp
      protocol: TLS
    tls:
      mode: SIMPLE
      credentialName: svc2-credential
    hosts:
    - svc2.demo.local
YAML

#  ---

kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: svc2
  namespace: demo
spec:
  hosts:
  - svc2.demo.local
  gateways:
  - demo/svc2
  http:
  - match:
    - uri:
        prefix: /
    route:
    - destination:
        host: svc2.demo.svc.cluster.local
        port:
          number: 8080
  tcp:
    - match:
        - port: 5005
      route:
        - destination:
            host: svc2.demo.svc.cluster.local
            port:
              number: 5005
YAML

INGRESS=$(kubectl -n istio-system get svc istio-ingressgateway  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo $INGRESS

nslookup $INGRESS

echo sleeping 5 seconds ...
sleep 5


# kubectl port-forward deploy/debug 5005:5005


curl -v \
  --cacert /Users/outlander/workDir/study/18k8s/09EKS-istio/svc1.crt \
  --connect-to svc1.demo.local:443:$INGRESS:443 \
  https://svc1.demo.local/hello?name=svc1-normal-run


curl -v \
  --cacert /Users/outlander/workDir/study/18k8s/09EKS-istio/svc2.crt \
  --connect-to svc2.demo.local:443:$INGRESS:443 \
  https://svc2.demo.local/hello?name=svc2-normal-run


curl -v \
  --cacert /Users/outlander/workDir/study/18k8s/09EKS-istio/svc1.crt \
  --connect-to svc1.demo.local:5005:$INGRESS:5005 \
  https://svc1.demo.local/hello?name=svc1-debug


curl -v \
  --cacert /Users/outlander/workDir/study/18k8s/09EKS-istio/svc2.crt \
  --connect-to svc2.demo.local:5005:$INGRESS:5005 \
  https://svc2.demo.local/hello?name=svc2-debug



