

```
oncall-engine Pod starts
    ↓
oncall-engine needs to connect to "postgresql" service
    ↓
oncall-engine queries kube-dns: "What's the IP of postgresql.default.svc.cluster.local?"
    ↓
kube-dns responds with postgresql service IP
    ↓
oncall-engine connects to that IP on port 5432
```



- When you don't specify toPorts, Cilium allows all ports and all protocols for that egress rule.

- TODO check if we are blocking all the outside traffic or we need this:

endpointSelector: {}
  ingress:
  - fromEntities:
    - cluster


- TODO: instead of every ns having default deny we can have :

apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: "default-deny"
spec:
  description: "Block all the traffic (except DNS) by default"
  egress:
  - toEndpoints:
    - matchLabels:
        io.kubernetes.pod.namespace: kube-system
        k8s-app: kube-dns
    toPorts:
    - ports:
      - port: '53'
        protocol: UDP
      rules:
        dns:
        - matchPattern: '*'
  endpointSelector:
    matchExpressions:
    - key: io.kubernetes.pod.namespace
      operator: NotIn
      values:
      - kube-system