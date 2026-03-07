# Deployment Troubleshooting

## Docker Compose

### Container exits immediately
- Check logs: `docker compose logs streamline`
- Verify port 9092 is not in use: `lsof -i :9092`
- Ensure sufficient memory (minimum 512MB recommended)

### Cannot connect from host
- Verify port mapping in docker-compose.yml
- Check `STREAMLINE_ADVERTISED_LISTENERS` is set correctly
- For Docker Desktop, use `localhost` not the container IP

## Kubernetes / Helm

### Pods stuck in Pending
- Check node resources: `kubectl describe nodes`
- Verify PVC can be provisioned: `kubectl get pvc`
- Check for scheduling constraints (nodeSelector, affinity)

### Helm install fails
- Verify Helm repo is added: `helm repo list`
- Check values file syntax: `helm lint ./helm/streamline`
- Review rendered templates: `helm template streamline ./helm/streamline`
