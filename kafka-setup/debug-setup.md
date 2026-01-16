# Debug Port 5005 Justification (NLB)

## Current Requirement
We need to support application debugging over JDWP on port 5005 in addition to normal HTTP traffic on port 80/443. The goal is to keep the developer experience consistent with the existing solution using a single service hostname and certificate:

- Service URL: `namespace-mars-payment-service.marsephe.aexp.com`
- HTTP traffic: port 443 (TLS) -> service:80
- Debug traffic: port 5005 (TLS) -> service:5005

## Why NLB Must Expose 5005
Istio terminates TLS at the ingress gateway and routes based on **port + SNI**. If we keep both HTTP and debug traffic under the **same hostname and same certificate**, the clean approach is to expose **two ports** on the NLB:

- `443/TCP` for HTTP (routed to `80` on pod)
- `5005/TCP` for JDWP debug (routed to `5005` on pod)

This allows:
- A single hostname and certificate.
- Consistent developer experience

If the NLB exposes only 443 and we still want to send debug traffic, we must route debug over 443 using **a different hostname** (SNI) so the gateway can distinguish the traffic. That forces:

- A second hostname (e.g., `namespace-debug-mars-payment-service.marsephe.aexp.com`)
- A second certificate (or a cert that includes that hostname)
- Extra developer steps and inconsistent UX

We attempted a single certificate with both SANs:

```
subjectAltName=DNS:namespace-mars-payment-service.marsephe.aexp.com,
DNS:namespace-debug-mars-payment-service.marsephe.aexp.com
```

This did not work as expected, while two separate certs (one per hostname) did work. Even with working SANs, it still adds operational complexity and breaks the “single URL” experience. The developers would have to make additional `-debug` string updates to url everytime they need to connect to debug port. 

## Ask
Please open **NLB listener 5005/TCP**. This preserves a consistent hostname and certificate and enables JDWP debugging alongside standard HTTP access while preventing the developer experience from getting cumbersome.
