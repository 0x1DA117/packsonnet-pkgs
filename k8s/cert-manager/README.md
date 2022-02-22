# cert-manager

## Development

The resources for each version are generated from the manifest files provided by
cert-manager.

Jsonnet version v0.18.0 is able to parse YAML files directly, but the JSON
representation is generated to support older versions of the Jsonnet compiler.

Command used to generate the JSON representation:

```bash
$ jsonnet \
  -o k8s/cert-manager/<VERSION>/_gen/cert-manager.json \
  --tla-str manifest="$(cat k8s/cert-manager/<VERSION>/cert-manager.yaml)" \
  tools/k8s/generateJSONFromManifest.jsonnet
```
