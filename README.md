# EKS - ISTIO - TERRAFORM 

  - EKS setup with istio ingress 

    Access endpoints
    ```
    # ------------
    # HTTP
    # ------------
    INGRESS=$(kubectl -n istio-system get svc istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    echo $INGRESS
    
    curl -s http://$INGRESS/
    # -> hello-from-pod-http

    # ------------
    # REDIS
    # ------------
    INGRESS=$(kubectl -n istio-system get svc istio-ingressgateway  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    echo $INGRESS

    redis-cli -h "$INGRESS" -p 6379 PING
    # -> PONG
    ```

  - tests for ingress for HTTP and non-http traffic