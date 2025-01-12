// nếu chưa có thì tạo ở trong này
```shell
cd /home/ec2-user/infra/k8s/app/ggg-temp-pod
k -n ggg apply -f pod.yaml

// sh
k -n ggg exec -it temporary-node-pod -- sh
```