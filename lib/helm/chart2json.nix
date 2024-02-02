{ runCommand, writeText, lib, kubernetes-helm, yq, cacert }:
with lib;
{
  # chart to template
  chart
  # release name
, name
  # namespace to install release into
, namespace ? null
  # values to pass to chart
, values ? { }
  # kubernetes version to template chart for
, kubeVersion ? null
  # whether to include CRD
, includeCRDs ? false
  # whether to include hooks
, noHooks ? false
  # Kubernetes api versions used for Capabilities.APIVersions (--api-versions)
, apiVersions ? null
  # remove values.schema.json if present
, removeValuesSchema ? false
  # extra args for helm template derivation
, extraDerivationArgs ? { }
}:
let
  valuesJsonFile = writeText "${name}-values.json" (builtins.toJSON values);
  # The `helm template` and YAML -> JSON steps are separate `runCommand` derivat}ions for easier debuggability
  chartNoValuesSchema = runCommand chart.name {} ''
    mkdir $out
    cp -r ${chart}/* $out
    rm -f $out/values.schema.json
  '';
  chart' = if removeValuesSchema
    then chartNoValuesSchema
    else chart;
  resourcesYaml = runCommand "${name}.yaml" (recursiveUpdate { nativeBuildInputs = [ kubernetes-helm cacert ]; } extraDerivationArgs) ''
    helm template "${name}" \
        ${optionalString (apiVersions != null && apiVersions != []) "--api-versions ${lib.strings.concatStringsSep "," apiVersions}"} \
        ${optionalString (kubeVersion != null) "--kube-version ${kubeVersion}"} \
        ${optionalString (namespace != null) "--namespace ${namespace}"} \
        ${optionalString (values != {}) "-f ${valuesJsonFile}"} \
        ${optionalString includeCRDs "--include-crds"} \
        ${optionalString noHooks "--no-hooks"} \
        ${chart'} >$out
  '';
in
runCommand "${name}.json" { } ''
  echo "the_path ${resourcesYaml}"
  touch $out
  # Remove null values
  ${yq}/bin/yq -Scs 'walk(
    if type == "object" then
      with_entries(select(.value != null))
    elif type == "array" then
      map(select(. != null))
    else
      .
    end)' ${resourcesYaml} > $out
''
