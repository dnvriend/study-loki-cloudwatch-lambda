
# Introduction
When running micro-services as containers, monitoring becomes very complex and difficult. That's where Prometheus, Grafana come to the rescue. Prometheus collects the metrics data and Grafana helps us to convert those metrics into beautiful visuals. Grafana allows you to query, visualize, and create an alert on metrics, no matter where they are stored. We can visualize metrics like CPU usage, memory usage, containers count, and much more. But there are few things that we can't visualize like container logs, it needs to be in tabular format with text data. For that, we can setup EFK (Elasticsearch + Fluentd + Kibana) stack, so Fluentd will collect logs from a docker container and forward it to Elasticsearch and then we can search logs using Kibana.

Grafana team has released Loki, which is inspired by Prometheus to solve this issue. So now, we don't need to manage multiple stacks to monitor the running systems like Grafana and Prometheus to monitor and EFK to check the logs.

## Grafana Loki
Loki is a horizontally-scalable, highly-available, multi-tenant log aggregation system inspired by Prometheus. It is designed to be very cost-effective and easy to operate. It does not index the contents of the logs, but rather a set of labels for each log stream. It uses labels from the log data to query.

## Fluent Bit
Fluent Bit (FB) is an open-source and multi-platform Log Processor and Forwarder which allows you to collect data/logs from different sources, unify and send them to multiple destinations. It's fully compatible with Docker and Kubernetes environments.

## Fluent bit Output plugins
The FB interface lets you define destinations for your data. Common destinations are remote services, local file systems, or other standard interfaces. Outputs are implemented as plugins. In ECS we use these containers that contains a FB that routes the logs to Loki using the [FB Loki Output Plugin](https://docs.fluentbit.io/manual/pipeline/outputs/loki)

```hcl
# image        = "grafana/fluent-bit-plugin-loki:2.0.0-amd64"
image        = "grafana/fluent-bit-plugin-loki:2.9.1"
```

## v2.9.1
Version 2.9.1 uses different keys:

```text
[2024/11/19 07:19:39] [error] [config] loki: unknown configuration property 'LabelKeys'. The following properties are allowed: tenant_id, tenant_id_key, labels, auto_kubernetes_labels, drop_single_key, label_keys, remove_keys, line_format, http_user, and http_passwd.
```

## v2.0.0-amd64
Version 2.0.0-amd64 uses different keys:

```text

```

## AWS Firelens for ECS
FireLens is a feature of Amazon Elastic Container Service (Amazon ECS) that allows you to easily run the Amazon Elastic Container Service (Amazon ECS) task definition to process and transform log data from containerized applications before storing them in a log storage service.

Amazon ECS converts the log configuration and generates the FB output configuration. The output configuration is mounted in the log routing container at `/fluent-bit/etc/fluent-bit.conf`.

### Metadata
By default, Amazon ECS adds additional fields in your log entries that help identify the source of the logs.

- ecs_cluster – The name of the cluster that the task is part of.
- ecs_task_arn – The full Amazon Resource Name (ARN) of the task that the container is part of.
- ecs_task_definition – The task definition name and revision that the task is using.
- ec2_instance_id – The Amazon EC2 instance ID that the container is hosted on. This field is only valid for tasks using the EC2 launch type.

You can set the `enable-ecs-log-metadata` to false if you do not want the metadata.

### Fluentbit output definition
The key-value pairs specified as options in the `logConfiguratio`n object are used to generate the Fluentd or Fluent Bit output configuration. The following is a code example from a Fluent Bit output definition.

```json
"logConfiguration": {
  "logDriver": "awsfirelens",
  "options": {
    "Name": "firehose",
    "region": "us-west-2",
    "delivery_stream": "my-stream",
    "log-driver-buffer-limit": "2097152"
  }
}
```

Will generate the following Fluent Bit configuration.

```text
[OUTPUT]
Name   firehose
Match  app-firelens*
region us-west-2
delivery_stream my-stream
```

> Note: FireLens manages the match configuration. You do not specify the match configuration in your task definition.

## Loki configuration

For Loki we can use this configuration

```hcl
logConfiguration = {
  logDriver = "awsfirelens"
  options   = {
    Name       = "loki"
    Url        = "http://internal-dnvriend-test-loki-alb-1422786846.us-east-1.elb.amazonaws.com/loki/api/v1/push"
    Labels     = "{job=\"firelens\",env=\"dev\",region=\"${data.aws_region.current.name}\"}"
    RemoveKeys = "container_id,ecs_task_arn"
    LabelKeys  = "container_name,ecs_task_definition,source,ecs_cluster"
    LineFormat = "key_value"
  }
}
```

that will generate the following configuration

```text
[OUTPUT]
Name loki
Match *
Url http://internal-dnvriend-test-loki-alb-1422786846.us-east-1.elb.amazonaws.com/loki/api/v1/push
Labels {job="firelens",env="dev",region="us-east-1"}
RemoveKeys container,ecs_task_arn
LabelKeys container_name,ecs_task_definition,source,ecs_cluster
LineFormat key_value
```

With the above configuration we have the following labels:

- container_name: httpbin
- ecs_cluster: dnvriend-test-grafana-cluster
- ecs_task_definition: dnvriend-test-httpbin:3
- env: dev
- job: firelens
- region: us-east-1
- service_name: httpbin
- source: stderr

The keys are all described in the [FB Loki Output Plugin](https://docs.fluentbit.io/manual/pipeline/outputs/loki), but the most important keys are:

#### Labels
Stream labels for API request. It can be multiple comma separated of strings specifying key=value pairs. In addition to fixed parameters, it also allows to add custom record keys (similar to label_keys property). More details in the Labels section.

#### label_keys
Optional list of record keys that will be placed as stream labels. This configuration property is for records key only. More details in the Labels section.

#### remove_keys
Optional list of keys to remove.

#### line_format
Format to use when flattening the record to a log line. Valid values are `json` or `key_value`. If set to json, the log line sent to Loki will be the Fluent Bit record dumped as JSON. If set to key_value, the log line will be each item in the record concatenated together (separated by a single space) in the format.

## ECS Fluentbit with environment variable configuration
The configuration to pass environment variables to the Fluentbit container is as follows:

1. Change the labels key of the logConfiguration so that it receives an environment variable for a key. The double dollar sign is for escaping the hcl string interpolation, we need a single dollar sign in the OUTPUT for fluentbit.

```hcl
Labels = "$${LOKI_LABELS}"
```

2. Add the environment variable to the environment variable of the fluentbit log forwarder container:

```hcl
{
  name         = "fluentbit"
  image        = "grafana/fluent-bit-plugin-loki:2.0.0-amd64"
  essential    = true
  cpu          = 0
  mountPoints  = []
  volumesFrom  = []
  environment  = []
  portMappings = []
  user         = "0"

  environment = [
    {
      name = "LOKI_LABELS"
      value = "{env=\"test_labels\",project_id=\"12345\",job=\"firelens\",region=\"us-east-1\",service=\"firelens\"}"
    }
  ]

  firelensConfiguration = {
    type    = "fluentbit"
    options = {
      "enable-ecs-log-metadata" : "true"
    }
  }

  logConfiguration = {
    logDriver = "awslogs"
    options   = {
      awslogs-group         = aws_cloudwatch_log_group.httpbin_log_group.name
      awslogs-region        = data.aws_region.current.name
      awslogs-stream-prefix = "fargate"
    }
  }
} 
```

## A single entry in the Labels
Alternatively, you can use a single entry in the Labels, but then you need to escape the double dollar sign. So you do not have to replace the whole line with the contents of the environment variable as shown above.

```hcl
logConfiguration = {
  logDriver = "awsfirelens"
  options = {
    Name       = "loki"
    Url        = "http://${aws_lb.loki_lb.dns_name}/loki/api/v1/push"
    Labels     = "{env=\"test_labels\",project_id=\"$${PROJECT_ID}\"}"
    RemoveKeys = "container_id,ecs_task_arn"
    LabelKeys  = "container_name,ecs_task_definition,source,ecs_cluster"
    LineFormat = "key_value"
  }
}
```

the log forwarder:


```hcl
{
  name  = "fluentbit"
  image = "grafana/fluent-bit-plugin-loki:2.0.0-amd64"
  # image        = "grafana/fluent-bit-plugin-loki:2.9.1" # note that it uses different keys for labels
  essential    = true
  cpu          = 0
  mountPoints  = []
  volumesFrom  = []
  environment  = []
  portMappings = []
  user         = "0"

  environment = [
    {
      name  = "PROJECT_ID"
      value = "543210"
    },
  ]

  firelensConfiguration = {
    type = "fluentbit"
    options = {
      "enable-ecs-log-metadata" : "true"
    }
  }

  logConfiguration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.httpbin_log_group.name
      awslogs-region        = data.aws_region.current.name
      awslogs-stream-prefix = "fargate"
    }
  }
}
```




## Resources

- https://docs.aws.amazon.com/AmazonECS/latest/developerguide/firelens-taskdef.html
- https://github.com/thakkaryash94/docker-grafana-loki-fluent-bit-sample
- https://grafana.com/docs/loki/latest/send-data/fluentbit/fluent-bit-loki-tutorial/
- https://github.com/aws/aws-for-fluent-bit/issues/788
- https://khalti.engineering/implementing-aws-firelens-with-grafana-loki-in-aws-ecs
- https://grafana.com/docs/loki/latest/get-started/labels/
- https://github.com/fluent/fluent-bit/issues/2821
- https://docs.fluentbit.io/manual/pipeline/outputs/loki
- https://docs.fluentbit.io/manual/1.0/configuration/variables
- 