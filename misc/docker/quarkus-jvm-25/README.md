## Build
```
docker build -t vjcspy/quarkus:jvm-25-1 .
docker push vjcspy/quarkus:jvm-25-1
```

## Build all platforms
```
docker buildx build --platform linux/amd64,linux/arm64 -t vjcspy/quarkus:jvm-25-1 --push .
```