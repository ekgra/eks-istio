# Namespace for Istio
resource "kubernetes_namespace_v1" "istio_system" {
  metadata {
    name = "istio-system"
    labels = {
      istio-operator-managed = "true"
    }
  }
}

# Optional pin; leave null to take latest from the repo
variable "istio_chart_version" {
  description = "Istio chart version (e.g., 1.22.x). Leave null for latest."
  type        = string
  default     = null
}

# 1) CRDs
resource "helm_release" "istio_base" {
  name             = "istio-base"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "base"
  namespace        = kubernetes_namespace_v1.istio_system.metadata[0].name
  version          = var.istio_chart_version
  create_namespace = false
  wait             = true

  depends_on = [kubernetes_namespace_v1.istio_system]
}

# 2) Control plane
resource "helm_release" "istiod" {
  name             = "istiod"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "istiod"
  namespace        = kubernetes_namespace_v1.istio_system.metadata[0].name
  version          = var.istio_chart_version
  create_namespace = false
  wait             = true

  values = [yamlencode({
    pilot = {
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { memory = "512Mi" }
      }
    }
  })]

  depends_on = [helm_release.istio_base]
}

# 3) Ingress gateway (NLB, instance mode) with HTTP + TCP(9092)
resource "helm_release" "istio_ingress" {
  name             = "istio-ingress"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "gateway"
  namespace        = kubernetes_namespace_v1.istio_system.metadata[0].name
  version          = var.istio_chart_version # or keep "1.28.1"
  create_namespace = false
  wait             = true

  values = [yamlencode({
    name = "istio-ingressgateway"

    service = {
      type = "LoadBalancer"
      annotations = {
        "service.beta.kubernetes.io/aws-load-balancer-type"                              = "nlb"
        "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type"                   = "instance"
        "service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled" = "true"
      }
      # NLB listeners → nodeports
      ports = [
        { name = "http2", port = 80, targetPort = 8080, protocol = "TCP" },
        { name = "https", port = 443, targetPort = 8443, protocol = "TCP" },
        { name = "tcp-kafka", port = 9092, targetPort = 9092, protocol = "TCP" },
      ]
      # externalTrafficPolicy = "Local" # if you later need client IP preservation
    }

    resources = {
      requests = { cpu = "100m", memory = "128Mi" }
      limits   = { memory = "256Mi" }
    }
  })]

  depends_on = [helm_release.istiod]
}
