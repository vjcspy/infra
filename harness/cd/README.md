# CD Service



## Các steps để triển khai 1 CD cho new Harness Service

Trước đó yêu cầu đã phải có:

- Harness delegate
- Harness kubernetes connector



Tạo Harness service

```shell
harness service --file harness/cd/whoami/service.yaml apply
```

Tạo environment(nếu chưa có). Ở đây là tạo dev env

```
harness environment --file harness/environment/dev-environment.yaml apply
```

Tạo infra cho dev environment(nếu chưa có)

```
harness infrastructure  --file harness/environment/dev-infra.yaml apply
```

Tạo pipeline

```
harness pipeline --file harness/cd/whoami/k8s-rolling-pipeline.yaml apply
```

