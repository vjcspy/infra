# K8S

## Install

Install k3s without traffik ingress

```shell
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable=traefik" sh -
```



## Dependencies

### Install nginx-ingress

Lưu ý phải cài đúng của kubernetes nhé, không cài của F5 thì cách hoạt động sẽ khác hoàn toàn (không sử dụng được các annotations)

```shell
helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx --create-namespace;
```

