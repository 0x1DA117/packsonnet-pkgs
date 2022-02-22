local packsonnet = import 'github.com/0xIDANT/packsonnet/main.libsonnet';
local resources = import '_gen/cert-manager.json';

packsonnet.k8s.package.new(
  function(config) resources,
)
