# Drone EKS Deploy

`drone-eks-deploy` is a [Drone-CI][drone] plugin that allows you to apply Kubernetes
manifests to EKS-based clusters.

[drone]: https://drone.io


## Table of Contents

- [Parameters](#parameters)
- [Secrets](#secrets)
- [Usage](#usage)


## Parameters

| Parameter    | Required? | Description                 |
|--------------|-----------|-----------------------------|
| `CLUSTER`    | Yes       | The EKS cluster's ARN.      |
| `MANIFEST`   | Yes       | The k8s manifest file path. |
| `NODE_ROLE`  | Yes       | The k8s node AMI role ARN.  |
| `AWS_REGION` | No        | The EKS cluster's region.   |

The `AWS_REGION` parameter will be set by default to the Drone's agent region.


## Secrets

`drone-eks-deploy` requires a set of [AWS credentials][aws-cred] (the access
and secret keys). These credentials must have enough permissions to perform the
desired changes at the EKS cluster.

The access and secret keys can be injected into the container via [Drone's
secrets][drone-secrets]. It is important to notice that the secrets must be
named according to the [environment variables the `awscli` looks
for][awscli-env]. If you manage multiple AWS credentials within Drone-CI, you
can use alternate names. Example:

```yaml
pipeline:
  deploy-staging:
    secrets:
      - aws_access_key: stg_aws_access_key
        aws_secret_key: stg_aws_secret_key

  deploy-production:
    secrets:
      - aws_access_key: prd_aws_access_key
        aws_secret_key: prd_aws_secret_key
```

[aws-cred]: https://docs.aws.amazon.com/general/latest/gr/aws-sec-cred-types.html
[drone-secrets]: http://docs.drone.io/manage-secrets
[awscli-env]: https://docs.aws.amazon.com/cli/latest/userguide/cli-environment.html


## Usage

```yaml
pipeline:
  deploy:
    image: caian/drone-eks-plugin:v1.1.0
    cluster: arn:aws:eks:us-east-1:001122334455:cluster/cluster-name
    node_role: arn:aws:iam::001122334455:role/eks-node-role
    manifest: k8s/deployment.yml
    secrets: [ aws_access_key, aws_secret_key ]
    when:
      branch: master
      event: tag
```
