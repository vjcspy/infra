# Fluent bit

## Install
If have not install helm 
```sh
helm repo add fluent https://fluent.github.io/helm-charts
helm repo update
```

Install helm chart by command
```shell
helm upgrade --install fluent-bit fluent/fluent-bit \
  -f fluent-bit-values.yaml \
  --namespace fluent-bit \
  --create-namespace
```

## DEBUG
Show xem config đã nhận từ custom file chưa
```aiignore
helm get values fluent-bit -n fluent-bit
```