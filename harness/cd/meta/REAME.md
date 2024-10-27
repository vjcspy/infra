# Meta CD

[TOC]



## Steps

### Configuration

#### Resolve Configuration

- project: lấy từ service variable `<+serviceVariables.meta_project_name>`
- namespace

### Pull code

#### Input

- name: string (dựa vào tên name để lấy ra được tên của brand project/NAME, ngoại trừ `stock` sẽ là lấy branch master luôn )

### Build code

#### Input

### Migrate Prisma

#### Input

- Prisma migrate: true/false (có run migrate production không?)

### Rollout

#### Input

- api: true/false (Có deploy api container không?)
- frontend: true/fase (Có deploy frontend nextjs không?)