# K8S

## Install

Install k3s without traffik ingress

```shell
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable=traefik" sh -
```



## Dependencies

### Install nginx-ingress

```shell
helm install nginx-ingress oci://ghcr.io/nginxinc/charts/nginx-ingress --version 1.4.0
```

