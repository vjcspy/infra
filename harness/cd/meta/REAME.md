# Meta CD

[TOC]



## Steps

### Configuration

#### Resolve Configuration

- `project`: lấy từ **pipeline** variable `<+pipeline.variables.meta_project_name>`
- `namespace` 

```tex
<+pipeline.stages.Configuration.spec.execution.steps.Resolve_Configuration.output.outputVariables.namespace>
```

- `gitBranch`

```tex
<+pipeline.stages.Configuration.spec.execution.steps.Resolve_Configuration.output.outputVariables.gitBranch>
```

- `sourceCodePath`: lưu ý source code path là trong container nên sẽ có định dạng /meta/PROJECT_NAME

```tex
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