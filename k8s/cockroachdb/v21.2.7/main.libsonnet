local packsonnet = import 'github.com/0x1DA117/packsonnet/main.libsonnet';
local k = import 'github.com/jsonnet-libs/k8s-libsonnet/1.23/main.libsonnet';

local default_config = import 'config.libsonnet';

local core = k.core.v1;
local apps = k.apps.v1;
local rbac = k.rbac.v1;
local policy = k.policy.v1;

local version = '21.2.7';

packsonnet.k8s.package.new(
  function(config) std.objectValues({
    labels::
      {
        'app.kubernetes.io/name': config.app_name,
        'app.kubernetes.io/version': version,
      },

    pvc::
      core.persistentVolumeClaim.new('%s-data' % config.app_name) +
      core.persistentVolumeClaim.spec.withAccessModes([
        'ReadWriteOnce',
      ]) +
      core.persistentVolumeClaim.spec.resources.withRequests({
        storage: '10Gi',
      }),

    service_account:
      core.serviceAccount.new(config.app_name) +
      core.serviceAccount.metadata.withLabels($.labels) +
      core.serviceAccount.metadata.withNamespace(config.namespace),

    role:
      rbac.role.new(config.app_name) +
      rbac.role.withRules([
        rbac.policyRule.withApiGroups(['']),
        rbac.policyRule.withResources(['secrets']),
        rbac.policyRule.withVerbs(['get']),
      ]) +
      rbac.role.metadata.withLabels($.labels) +
      rbac.role.metadata.withNamespace(config.namespace),

    role_binding:
      rbac.roleBinding.new(config.app_name) +
      rbac.roleBinding.bindRole($.role) +
      rbac.roleBinding.withSubjects(
        rbac.subject.fromServiceAccount($.service_account)
      ) +
      rbac.roleBinding.metadata.withLabels($.labels) +
      rbac.roleBinding.metadata.withNamespace(config.namespace),

    service_public:
      core.service.new(
        '%s-public' % config.app_name,
        $.labels,
        [
          core.servicePort.newNamed('grpc', 26257, 26257),
          core.servicePort.newNamed('http', 8080, 8080),
        ]
      ) +
      core.service.metadata.withLabels($.labels) +
      core.service.metadata.withNamespace(config.namespace),

    service_headless:
      $.service_public +
      core.service.metadata.withName(config.app_name) +
      core.service.spec.withClusterIP('None') +
      core.service.spec.withPublishNotReadyAddresses(true),

    pod_disruption_budget:
      policy.podDisruptionBudget.new(config.app_name) +
      policy.podDisruptionBudget.metadata.withLabels($.labels) +
      policy.podDisruptionBudget.metadata.withNamespace(config.namespace) +
      policy.podDisruptionBudget.spec.withMaxUnavailable(1) +
      policy.podDisruptionBudget.spec.selector.withMatchLabels($.labels),

    container::
      core.container.new(config.app_name, 'cockroachdb/cockroach:v%s' % version) +
      core.container.withImagePullPolicy('IfNotPresent') +
      core.container.withCommand([
        '/bin/bash',
        '-ecx',
        std.join(
          ' ',
          [
            'exec',
            '/cockroach/cockroach',
            'start',
            '--logtostderr',
            '--certs-dir',
            '/cockroach/cockroach-certs',
            '--advertise-host',
            '$(hostname -f)',
            '--http-addr',
            '0.0.0.0',
            '--join',
            std.join(',', std.makeArray(3, function(i) '%s-%s.%s' % [config.app_name, i, $.service_headless.metadata.name])),
            '--cache',
            '$(expr $MEMORY_LIMIT_MIB / 4)MiB',
            '--max-sql-memory',
            '$(expr $MEMORY_LIMIT_MIB / 4)MiB',
          ]
        ),
      ]) +
      core.container.withPorts([
        core.containerPort.newNamed('grpc', 26257),
        core.containerPort.newNamed('http', 8080),
      ]) +
      core.container.withEnv([
        core.envVar.new('COCKROACH_CHANNEL', 'kubernetes-secure'),
        core.envVar.withName('GOMAXPROCS') +
        core.envVar.valueFrom.resourceFieldRef.withResource('limits.cpu') +
        core.envVar.valueFrom.resourceFieldRef.withDivisor('1'),
        core.envVar.withName('MEMORY_LIMIT_MIB') +
        core.envVar.valueFrom.resourceFieldRef.withResource('limits.memory') +
        core.envVar.valueFrom.resourceFieldRef.withDivisor('1Mi'),
      ]) +
      core.container.withVolumeMounts([
        core.volumeMount.new('data', '/cockroach/cockroach-data', false),
        core.volumeMount.new('certs', '/cockroach/cockroach-certs', false),
      ]) +
      core.container.readinessProbe.withInitialDelaySeconds(10) +
      core.container.readinessProbe.withPeriodSeconds(5) +
      core.container.readinessProbe.withFailureThreshold(2) +
      core.container.readinessProbe.httpGet.withPath('/health?ready=1') +
      core.container.readinessProbe.httpGet.withPort('http') +
      core.container.readinessProbe.httpGet.withScheme('HTTPS') +
      core.container.resources.withRequests({
        cpu: '2',
        memory: '8Gi',
      }) +
      core.container.resources.withLimits({
        cpu: '2',
        memory: '8Gi',
      }),

    statefulset:
      apps.statefulSet.new(
        config.app_name,
        replicas=3,
        podLabels=$.labels,
        containers=[
          $.container,
        ],
        volumeClaims=[
          $.pvc,
        ],
      ) +
      apps.statefulSet.metadata.withNamespace(config.namespace) +
      apps.statefulSet.spec.withPodManagementPolicy('Parallel') +
      apps.statefulSet.spec.updateStrategy.withType('RollingUpdate') +
      apps.statefulSet.spec.template.spec.withTerminationGracePeriodSeconds(60) +
      apps.statefulSet.spec.template.spec.withVolumes([
        core.volume.fromPersistentVolumeClaim('data', $.pvc.metadata.name),
        core.volume.fromSecret('certs', config.cert_secret_name) +
        core.volume.secret.withDefaultMode(256),
      ]),
  }),
  defaultConfig=default_config,
)
