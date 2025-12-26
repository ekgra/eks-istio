# EKS + Istio Ingress Gateway - Complete Demo

A comprehensive Terraform + Kubernetes setup demonstrating **EKS with Istio Ingress Gateway** handling HTTP, Redis, Cassandra and Kafka workloads with various TLS configurations.

## 🏗️ Infrastructure Architecture

### AWS/EKS Layer (Terraform)

- **Cluster**: Amazon EKS 1.31 (configurable via `var.eks_version`)
- **Node Groups**:
  - **Spot Instances** (primary): `t3.small`, `t3a.small`, `t2.small`, `t3.medium` — cost-optimized
  - **On-Demand Instances** (fallback): `t3.small`, `t3a.small`, `t3.medium` — reliability fallback (disabled by default)
- **Networking**:
  - VPC: `10.10.0.0/16`
  - Public Subnets: 2 subnets across 2 AZs (`/20` blocks)
  - Internet Gateway for public access
- **Load Balancer**: AWS Network Load Balancer (NLB, instance mode) via Istio Ingress Gateway
- **Security Groups**:
  - NodePort range: `30000-32767` from `allowed_cidr` (default: `0.0.0.0/0` — restrict to your IP for security)
  - Internal VPC traffic: All protocols allowed (`10.10.0.0/16`)
  - Kubelet (10250), istiod webhook (15017): From EKS control plane only

### Kubernetes Layer (Istio + Workloads)

- **Istio**: Base, Istiod control plane, and Ingress Gateway (Helm charts)
- **Workloads**:
  - **HTTP Service**: Simple echo server (port 8080)
  - **Redis Instances**: Redis 7 Alpine containers (port 6379 or TLS)
  - **Kafka Broker**: Confluent Kafka with Zookeeper (port 9092 internal, 443 external)
  - **Cassandra**: Cassandra 4.1 cluster (port 9042)
- **Add-ons**: VPC CNI, CoreDNS, kube-proxy

---

## 📦 Workloads & Access Patterns

### 1. HTTP and Redis(TCP) Workload - Plaintext Ingress

**File**: `manifests/plain-http_redis.sh`

Deploy an HTTP echo service with plaintext (HTTP) ingress + basic Redis service.

```bash
bash manifests/plain-http_redis.sh
```

**Access**:
```bash
# Get NLB endpoint
INGRESS=$(kubectl -n istio-system get svc istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo $INGRESS

# Test HTTP
curl --connect-to http.demo.local:80:$INGRESS:80 http://http.demo.local/
# Response: hello-from-pod-http

# Test Redis (plaintext, port 6379)
redis-cli -h "$INGRESS" -p 6379 PING
# Response: PONG
```

**Components**:
- `Deployment`: http (hashicorp/http-echo)
- `Service`: http (port 8080)
- `Gateway`: HTTP on port 80
- `VirtualService`: Routes to http service
- `Deployment`: redis (redis:7-alpine, plaintext)
- `Service`: redis (port 6379)
- `Gateway`: TCP on port 6379
- `VirtualService`: Routes to redis service

---

### 2. HTTP Workload - TLS Termination

**File**: `manifests/tls_http.sh`

Deploy HTTP service with TLS-terminated ingress (HTTPS port 443).

```bash
bash manifests/tls_http.sh
```

**What it does**:
1. Generates self-signed certificate for `http.demo.local`
2. Creates Kubernetes TLS secret in `istio-system` namespace
3. Deploys HTTP echo service with Istio Gateway (HTTPS/443)

**Access**:
```bash
# Get NLB endpoint
INGRESS=$(kubectl -n istio-system get svc istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Test HTTPS with certificate verification
curl -v \
  --cacert ./http.crt \
  --connect-to http.demo.local:443:$INGRESS:443 \
  https://http.demo.local/
# Response: hello-from-pod-http
```

**Components**:
- `Deployment`: http (hashicorp/http-echo)
- `Service`: http (port 8080)
- `Gateway`: HTTPS on port 443 (TLS mode: SIMPLE, credential: http-credential)
- `VirtualService`: Routes to http service
- `Secret`: http-credential (TLS certificate/key in istio-system)

**Key Concept**: NLB:443 → Istio Gateway (decrypts TLS) → Pod:8080 (plaintext)

---

### 3. Redis(TCP) Workload - TLS Passthrough

**File**: `manifests/tls_redis.sh`

Deploy Redis instances with **TLS passthrough** (Istio does NOT decrypt).

```bash
bash manifests/tls_redis.sh
```

**What it does**:
1. Generates CA certificate and server certificates for redis1 & redis2
2. Deploys Redis pods with TLS enabled (configured via redis-server args)
3. Creates Istio Gateway with `tls.mode: PASSTHROUGH` (SNI-based routing)

**Access**:
```bash
# redis-cli with TLS (using CA cert and SNI)
redis-cli --tls --cacert ./ca.crt --sni redis1.demo.local -h redis1.demo.local -p 9092 PING
redis-cli --tls --cacert ./ca.crt --sni redis2.demo.local -h redis2.demo.local -p 9092 PING

# Response: PONG
```

**Components**:
- `Deployment`: redis1, redis2 (redis:7-alpine with TLS enabled)
- `Service`: redis1, redis2 (port 6379)
- `Gateway`: TLS on port 9092 (mode: PASSTHROUGH, SNI-based routing)
- `VirtualService`: TCP routes based on SNI host
- `Secret`: redis1-tls, redis2-tls (CA + server certs/keys)

**Key Concept**: NLB:9092 → Istio Gateway (routes by SNI, no decryption) → Pod:6379 (TLS)

**Why PASSTHROUGH?** Redis clients expect TLS handshake; Istio must not intercept.

---

### 4. Redis(TCP) Workload - TLS Termination

**File**: `manifests/tls_term_redis.sh`

Deploy Redis instances with **TLS termination** (Istio decrypts, backend plaintext).

```bash
bash manifests/tls_term_redis.sh
```

**What it does**:
1. Generates self-signed certificates for redis1 & redis2
2. Deploys plain Redis pods (no TLS at container level)
3. Creates Istio Gateway with `tls.mode: SIMPLE` (TLS terminated by Istio)
4. VirtualService routes decrypted traffic to plaintext Redis pods

**Access**:
```bash
# Get NLB endpoint
INGRESS=$(kubectl -n istio-system get svc istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# redis-cli with TLS
redis-cli --tls --cacert ./redis1.crt --sni redis1.demo.local -h redis1.demo.local -p 6379 PING
redis-cli --tls --cacert ./redis2.crt --sni redis2.demo.local -h redis2.demo.local -p 6379 PING

# Response: PONG
```

**Components**:
- `Deployment`: redis1, redis2 (redis:7-alpine, plaintext)
- `Service`: redis1, redis2 (port 6379)
- `Gateway`: TLS on port 6379 (mode: SIMPLE, credential: redis1-credential, redis2-credential)
- `VirtualService`: TCP routes (Istio decrypts before routing)
- `Secret`: redis1-credential, redis2-credential (TLS cert/key in istio-system)

**Key Concept**: NLB:6379 → Istio Gateway (decrypts TLS) → Pod:6379 (plaintext Redis)

---

### 5. Kafka Workload - TLS Termination

**File**: `manifests/tls_term_kafka.sh`

Deploy Kafka broker with **TLS termination** (Istio decrypts, backend plaintext). Includes Zookeeper for metadata management.

```bash
bash manifests/tls_term_kafka.sh
```

**What it does**:
1. Generates self-signed certificate for `cp-kafka.demo.local`
2. Deploys Zookeeper (single-node, port 2181)
3. Deploys Kafka broker with dual listeners:
   - **INTERNAL**: Port 9092 (plaintext, for in-cluster pods)
   - **EXTERNAL**: Port 443 (plaintext after Istio TLS termination)
4. Creates Istio Gateway with `tls.mode: SIMPLE` (TLS terminated by Istio)
5. Generates Java truststore for TLS client connections
6. Creates `kafka-topics` commands to test topic creation

**Access**:
```bash
# Get NLB endpoint (for external clients)
INGRESS=$(kubectl -n istio-system get svc istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Create topic (with TLS)
kafka-topics \
  --bootstrap-server cp-kafka.demo.local:443 \
  --create \
  --topic test-topic \
  --partitions 1 \
  --replication-factor 1 \
  --command-config client-ssl.properties

# List topics
kafka-topics \
  --bootstrap-server cp-kafka.demo.local:443 \
  --list \
  --command-config client-ssl.properties
```

**Components**:
- `Deployment`: zk (Zookeeper, port 2181)
- `Service`: zk (Zookeeper service)
- `Deployment`: cp-kafka (Confluent Kafka)
  - INTERNAL listener: 9092 (PLAINTEXT)
  - EXTERNAL listener: 443 (PLAINTEXT after TLS termination)
- `Service`: cp-kafka (exposes both ports)
- `Gateway`: TLS on port 443 (mode: SIMPLE, credential: kafka-credential)
- `VirtualService`: TCP route (Istio decrypts before routing to port 443)
- `Secret`: kafka-credential (TLS cert/key in istio-system)
- Java Truststore: `kafka-truststore.jks` (for TLS verification)
- Client Config: `client-ssl.properties` (SSL settings for kafka-topics CLI)

**Key Concept**: NLB:443 → Istio Gateway (decrypts TLS) → Pod:443 (plaintext Kafka EXTERNAL listener)

**Architecture**:
```
External Client (TLS)
        ↓
NLB:443
        ↓
Istio Gateway (TLS termination)
        ↓
Kafka Pod:443 (EXTERNAL listener, plaintext)
        ↓
Kafka Internal (Pod:9092 for inter-pod communication)
        ↓
Zookeeper:2181
```

**Why dual listeners?**
- **INTERNAL (9092)**: Pods within cluster communicate plaintext (faster, VPC-isolated)
- **EXTERNAL (443)**: External clients use TLS (encrypted, ingress-managed)
- **Different advertised endpoints**: Kafka tells clients which address to use based on listener

---

## 🚀 Quick Start

### Prerequisites

- AWS account with sufficient permissions (EKS, EC2, VPC, IAM)
- Terraform >= 1.0
- `kubectl` configured (or run `aws eks update-kubeconfig` after Terraform apply)
- `redis-cli` for testing Redis workloads
- `openssl` for certificate generation

### 1. Deploy Infrastructure (Terraform)

```bash
# Clone or navigate to repo
cd /Users/outlander/workDir/study/18k8s/09EKS-istio

# Configure variables (optional)
# cat terraform.tfvars  # Edit if needed

# Initialize and apply
terraform init
terraform apply

# Get outputs
terraform output

# Configure kubectl
aws eks update-kubeconfig --name demo-eks-istio --region ap-southeast-2
```

**Cost Note**: Spot Instances cost ~60-80% less than On-Demand. On-Demand fallback is disabled by default to minimize costs.

### 2. Deploy Workloads

Choose one or multiple scripts:

```bash
# HTTP + plaintext Redis
bash manifests/plain-http_redis.sh

# HTTP + TLS-terminated
bash manifests/tls_http.sh

# Redis with TLS passthrough
bash manifests/tls_redis.sh

# Redis with TLS termination
bash manifests/tls_term_redis.sh

# Kafka with Zookeeper (TLS termination)
bash manifests/tls_term_kafka.sh
```

### 3. Verify Istio Gateway

```bash
# Wait for NLB to get an endpoint (2-3 minutes)
kubectl -n istio-system get svc istio-ingressgateway
```

### 4. Test Access

See **Workloads & Access Patterns** section above for test commands.

---

## 🔐 Security Considerations

### Current Setup (Default)

- ✅ **VPC Isolation**: All nodes in private communication via VPC CIDR
- ✅ **Istio mTLS (STRICT mode)**: Pod-to-pod encryption enforced
- ⚠️ **Wide open external access**: `allowed_cidr = "0.0.0.0/0"` (for demo)

### Hardening Recommendations

1. **Restrict `allowed_cidr`**:
   ```bash
   terraform apply -var="allowed_cidr=YOUR_IP/32"
   ```

2. **Use Istio AuthorizationPolicy** for pod-level access control:
   ```yaml
   apiVersion: security.istio.io/v1beta1
   kind: AuthorizationPolicy
   metadata:
     name: redis-policy
     namespace: demo
   spec:
     selector:
       matchLabels:
         app: redis
     rules:
     - from:
       - source:
           principals: ["cluster.local/ns/demo/sa/client"]
       to:
       - operation:
           ports: ["6379"]
   ```

3. **Enable Private Endpoint** (if not requiring external access):
   ```terraform
   endpoint_private_access = true
   endpoint_public_access = false  # or restrict via CIDR
   ```

4. **Use AWS Certificate Manager (ACM)** instead of self-signed certs for production.

---

## 📊 Istio Gateway Port Mapping

| NLB Port | Pod Port | Service Port | Protocol | TLS Mode | Use Case |
|----------|----------|--------------|----------|----------|----------|
| 80       | 8080     | 8080         | HTTP     | None     | Plaintext HTTP |
| 443      | 8080     | 8080         | HTTPS    | SIMPLE   | TLS-terminated HTTP |
| 443      | 9042     | 9042         | TCP      | SIMPLE   | TLS-terminated Cassandra |
| 443      | 443      | 443          | TCP      | SIMPLE   | TLS-terminated Kafka (EXTERNAL listener) |
| 6379     | 6379     | 6379         | TCP      | SIMPLE   | TLS-terminated Redis |
| 9092     | 6379     | 6379         | TCP      | PASSTHROUGH | Redis with pod-level TLS |

---

## 📁 File Structure

```
.
├── addon.tf              # EKS add-ons (VPC CNI, CoreDNS, kube-proxy)
├── eks.tf                # EKS cluster, node groups, IAM roles
├── istio_helm.tf         # Istio Helm releases (base, istiod, ingress gateway)
├── locals.tf             # Local variables (AZs, subnets)
├── main.tf               # (empty, for organization)
├── network.tf            # VPC, subnets, security groups, IGW
├── outputs.tf            # Terraform outputs
├── provider.tf           # AWS + Kubernetes provider config
├── variables.tf          # Input variables
├── versions.tf           # Terraform version constraint
├── terraform.tfstate*    # State files (managed by Terraform)
│
├── manifests/
│   ├── plain-http_redis.sh       # HTTP plaintext + Redis plaintext
│   ├── tls_http.sh               # HTTP TLS-terminated
│   ├── tls_redis.sh              # Redis TLS passthrough (2 instances)
│   ├── tls_term_redis.sh         # Redis TLS-terminated (2 instances)
│   ├── tls_term_kafka.sh         # Kafka + Zookeeper (TLS termination)
│   ├── tls_term_cassandra.sh     # Cassandra (TLS termination)
│   └── debug.sh                  # Debugging utilities
│
├── puml/
│   ├── 00mTLS_strict.puml     # mTLS strict mode diagram
│   ├── 01tcp_current.puml     # Current TCP routing diagram
│   └── 02tcp_actual.puml      # Actual TCP routing diagram
│
└── README.md                   # This file
```

---

## 🔧 Variables (Terraform)

Key variables in `variables.tf`:

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | `ap-southeast-2` | AWS region for deployment |
| `cluster_name` | `demo-eks-istio` | EKS cluster name |
| `vpc_cidr` | `10.10.0.0/16` | VPC CIDR block |
| `allowed_cidr` | `0.0.0.0/0` | CIDR allowed to access NodePort range (restrict this!) |
| `eks_version` | `1.31` | Kubernetes version |
| `node_desired` | `2` | Desired Spot instances |
| `node_max` | `4` | Max Spot instances |
| `instance_types` | `[t3.small, ...]` | Instance types for Spot |
| `od_node_desired` | `0` | Desired On-Demand instances (disabled by default) |
| `istio_chart_version` | `null` | Istio Helm chart version (null = latest) |

---

## 📝 Typical Workflows

### Test Only Plaintext (Lowest Complexity)
```bash
terraform apply
bash manifests/plain-http_redis.sh
# Curl HTTP endpoint + redis-cli to plaintext Redis
```

### Test HTTP TLS
```bash
terraform apply
bash manifests/tls_http.sh
# Curl HTTPS endpoint with custom CA
```

### Test Redis TLS Passthrough (Advanced)
```bash
terraform apply
bash manifests/tls_redis.sh
# redis-cli with --tls and SNI routing through Istio
```

### Test Redis TLS Termination
```bash
terraform apply
bash manifests/tls_term_redis.sh
# redis-cli with TLS to Istio; plaintext pod-to-pod
```

### Test Kafka TLS Termination
```bash
terraform apply
bash manifests/tls_term_kafka.sh
# Create topics, produce/consume with TLS via Istio
# Internal pods use plaintext on port 9092
```

---

## 🛠️ Cleanup

```bash
# Delete Kubernetes resources first
kubectl delete namespace demo

# Destroy Terraform resources
terraform destroy
```

---

## 📚 References

- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Istio Ingress Gateway](https://istio.io/latest/docs/tasks/traffic-management/ingress/ingress-control/)
- [Istio TLS Passthrough](https://istio.io/latest/docs/tasks/traffic-management/ingress/tls/)
- [Redis TLS Configuration](https://redis.io/docs/management/security/encryption/)

---

**Last Updated**: December 2025
