# Harness

## Setup

### Kubernetes Delegate

Follow theo document để install latest version (Project Settings -> Delegates)

### Github PAT

Sử dụng để có quyên access vào github thông qua token. Sau khi generate PAT token thì run this command to create secret in `Harness`

```shell
harness secret apply --token GITHUB-PAT --secret-name "harness_gitpat"
```

### Github connector

Tạo connector để có thể access được vào các repo của mình

```shell
harness connector --file harness/connector/github-connector.yaml apply --git-user vjcspy
```
