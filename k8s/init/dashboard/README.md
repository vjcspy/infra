# k8s-dashboard



## Install

1. Install from helm

```bash
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
helm repo update
helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
--create-namespace --namespace kubernetes-dashboard \
```

2 ~~Cert generated from Cloudflare~~

Không cần làm step này nữa

```bash
# ví dụ tạo tls secret cho k8s-dashboard
kubectl create secret tls kubernetes-dashboard-tls --key common.key --cert common.crt -n kubernetes-dashboard
```

3. Sau đó apply toàn bộ thư mục dashboard để tạo ingress, service account(dùng để access)

```bash
k apply -f dashboard
```

## Access dashboard
Vẫn chưa hiểu sao expose bằng ingress lại lỗi, phải sử dụng cách expose bằng NodePort sau đó truy cập bằng `https://18.138.53.203:32260/#/workloads?namespace=default`
Với NodePort là 32260 (nhớ open port ở security group)

### Generate token to access

```bash
# short time
kubectl -n kubernetes-dashboard create token admin-user

# long time
kubectl get secret admin-user -n kubernetes-dashboard -o jsonpath={".data.token"} | base64 -d
```

