# Meta CD

[TOC]



## Steps

### Configuration

#### Resolve Configuration

- project: lấy từ service variable `<+serviceVariables.meta_project_name>`

- namespace

- gitBranch

```shell
<+pipeline.stages.Configuration.spec.execution.steps.Resolve_Configuration.output.outputVariables.gitBranch>
```

- sourceCodePath

```shell
<+pipeline.stages.Configuration.spec.execution.steps.Resolve_Configuration.output.outputVariables.sourceCodePath>
```



### Pull code

Sử dụng built-in git clone của Harness

### Build code

#### Input

### Migrate Prisma

#### Input

- Prisma migrate: true/false (có run migrate production không?)

### Rollout

#### Input

- api: true/false (Có deploy api container không?)
- frontend: true/fase (Có deploy frontend nextjs không?)