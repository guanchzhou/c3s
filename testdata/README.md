# C3S Test Data

This directory contains test data copied from k9s for realistic Kubernetes resource examples.

## Structure

```
testdata/k8s/
├── pods/         - Pod JSON manifests
├── deployments/  - Deployment JSON manifests  
├── services/     - Service JSON manifests
├── nodes/        - Node JSON manifests
├── config/       - Kubeconfig files
```

## Source

All testdata is copied from k9s project:
- https://github.com/derailed/k9s

### Files

- `pods/po.json` - nginx pod in default namespace (Running, 1/1 ready)
- `deployments/dp.json` - icx-db deployment in icx namespace
- `services/svc.json` - dictionary1 ClusterIP service
- `nodes/no.json` - minikube node with full specs (v1.15.2)
- `config/kubeconfig` - test kubeconfig (fred, blee, zorg contexts)

## Usage

These files are embedded at compile time using `@embedFile` and parsed by fixtures to provide realistic test data.

See:
- `src/fixtures/pods_data.zig` - Parses pod JSON
- `src/fixtures/k8s_data.zig` - Parses node/cluster data
