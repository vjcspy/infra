# Cert-Manager

## 1. Overview
Now, we will use cert-manager to manage our certificates instead of manually declaring them in values.yaml.

```shell
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.crds.yaml
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager -n cert-manager --create-namespace
```

## 2. Sơ đồ luồng kết nối

```

Client (HTTPS)
↓
Cloudflare Edge (HTTPS, SSL mode: Full)
↓
Origin Server (NGINX Ingress Controller)
↓
Kubernetes Service / Pod

````

- Cloudflare kiểm tra origin bằng **self-signed cert** → chấp nhận khi SSL mode = Full.

---

## 3. Các bước thực hiện

### 3.1. Cài cert-manager
```bash
# Bước 1: Cài CRDs của cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.crds.yaml

# Bước 2: Thêm Helm repo
helm repo add jetstack https://charts.jetstack.io

# Bước 3: Cài cert-manager vào namespace cert-manager
helm install cert-manager jetstack/cert-manager -n cert-manager --create-namespace
````

> 💡 **Giải thích**: CRD (Custom Resource Definition) là các loại resource mới mà cert-manager định nghĩa (`Certificate`, `Issuer`, `ClusterIssuer`, `Order`, `Challenge`). Phải apply trước để Kubernetes hiểu các loại resource này.

---

### 3.2. Tạo Root CA self-signed và ClusterIssuer dùng chung

Tạo file `ca-selfsigned.yaml`:

```yaml
# 1) ClusterIssuer selfsigned-root (tạo CA gốc tự ký)
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-root
spec:
  selfSigned: {}

---
# 2) Certificate k8s-root-ca (dùng selfsigned-root để sinh root CA)
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: k8s-root-ca
  namespace: cert-manager
spec:
  isCA: true
  commonName: k8s-root-ca
  secretName: k8s-ca
  issuerRef:
    name: selfsigned-root
    kind: ClusterIssuer

---
# 3) ClusterIssuer k8s-ca-issuer (dùng root CA để ký cert con)
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: k8s-ca-issuer
spec:
  ca:
    secretName: k8s-ca
```

Apply:

```bash
kubectl apply -f ca-selfsigned.yaml
```

> 💡 **Lưu ý**: Bước này chỉ cần làm **1 lần cho cả cluster**. Sau đó tất cả Ingress đều có thể dùng `k8s-ca-issuer` để xin cert.

---

### 3.3. Tạo Ingress dùng cert từ CA nội bộ

Ví dụ `myapp-ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp
  namespace: default
  annotations:
    cert-manager.io/cluster-issuer: k8s-ca-issuer
spec:
  ingressClassName: nginx
  tls:
    - hosts: ["app.example.com"]
      secretName: myapp-tls
  rules:
    - host: app.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: myapp-svc
                port:
                  number: 80
```

Apply:

```bash
kubectl apply -f myapp-ingress.yaml
```

---

## 4. Kiểm tra kết quả

### 4.1. Xem chứng chỉ được cấp

```bash
kubectl describe certificate myapp-tls -n default
kubectl get secret myapp-tls -n default
```

### 4.2. Kiểm tra trạng thái cert-manager

```bash
kubectl get pods -n cert-manager
kubectl get certificaterequest,certificate,order,challenge -A
```

---

## 5. Cấu hình Cloudflare

* **SSL/TLS mode**: chọn **Full** (không strict).
  → Cloudflare sẽ chấp nhận self-signed cert từ origin.
* Bật **Proxy (orange cloud)** nếu muốn ẩn IP origin.

---

## 6. Ghi chú

* Self-signed chỉ dùng được với **Full** (không strict).
  Nếu muốn dùng **Full (strict)** → cần cert hợp lệ từ CA tin cậy hoặc **Cloudflare Origin CA**.
* Thời hạn root CA nên đặt dài (5–10 năm). Các cert con có thể ngắn hơn (90 ngày, 1 năm).
* Khi cert con gần hết hạn, cert-manager sẽ tự động gia hạn và NGINX reload mà không downtime.

---

## 7. Tóm tắt quy trình

1. Cài cert-manager (CRDs + Helm chart).
2. Tạo Root CA self-signed (`selfsigned-root` + `k8s-root-ca`).
3. Tạo ClusterIssuer (`k8s-ca-issuer`) dùng root CA này để ký cert con.
4. Với mỗi Ingress:

    * Thêm annotation `cert-manager.io/cluster-issuer: k8s-ca-issuer`.
    * Khai báo `tls:` với `secretName` bất kỳ.
5. Cloudflare SSL/TLS mode = Full.




