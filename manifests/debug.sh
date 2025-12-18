aws eks update-kubeconfig --name demo-eks-istio --region ap-southeast-2

istioctl x describe pod -n demo http-696f5f9774-n68db
istioctl x describe pod -n demo redis-5cd7c55898-xxbrq
istioctl x describe pod -n demo redis1-fb895d5df-rv69p 

istioctl pc cluster http-696f5f9774-n68db -n istio-system 
istioctl pc cluster redis-5cd7c55898-tf8k2 -n istio-system 

POD=$(kubectl -n istio-system get pod -l istio=ingressgateway -o jsonpath='{.items[0].metadata.name}')
istioctl pc cluster $POD -n istio-system | grep http
istioctl pc cluster $POD -n istio-system | grep redis

INGRESS=$(kubectl -n istio-system get svc istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
openssl s_client   -connect "${INGRESS}:9092"   -servername redis.demo.local   -CAfile ca.crt
openssl s_client   -connect redis1.demo.local:9092   -servername redis1.demo.local   -CAfile ca.crt

curl -v \
  --cacert pod-http-demo.crt \
  --connect-to pod-http.demo.local:443:$INGRESS:443 \
  https://pod-http.demo.local/