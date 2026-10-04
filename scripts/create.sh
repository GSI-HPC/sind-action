#!/usr/bin/env bash
set -euo pipefail

# The yq expressions below need mikefarah yq v4, not the Python yq wrapper.
yq_version=$(yq --version 2>/dev/null || true)
if [[ "$yq_version" != *mikefarah/yq*" v4."* ]]; then
  echo "::error::mikefarah yq v4 (https://github.com/mikefarah/yq) is required, found: ${yq_version:-none}"
  exit 1
fi

# Temporary files: the input for yq and one config per inline cluster
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
input_file="${tmp_dir}/clusters.yml"
printf '%s\n' "$SIND_CLUSTERS" > "$input_file"

# `sind status` was replaced by `sind get cluster` in sind v0.9.0.
sind_version=$(sind version --json | jq -r '.version')
if [[ "$(printf '%s\n' 0.9.0 "$sind_version" | sort -V | head -n1)" == "0.9.0" ]]; then
  status_cmd=(get cluster)
else
  status_cmd=(status)
fi

# `sind create cluster --wait` came after sind v0.10.0; sind validates the value.
wait_flags=()
if [[ -n "${SIND_WAIT:-}" ]]; then
  if [[ "$(printf '%s\n' 0.10.0 "$sind_version" | sort -V | tail -n1)" != "0.10.0" ]]; then
    wait_flags=(--wait "$SIND_WAIT")
  else
    echo "::warning::The wait input needs a sind release after v0.10.0 and is ignored with sind ${sind_version}"
  fi
fi

# An empty input creates no clusters; anything else must be a list.
input_kind=$(yq 'kind' "$input_file")
if [[ "$input_kind" != "seq" && "$(yq 'tag' "$input_file")" != "!!null" ]]; then
  echo "::error::clusters must be a YAML list, with one '- ' entry per cluster (got a ${input_kind})"
  exit 1
fi

clusters=""
count=$(yq 'length' "$input_file")

for ((i = 0; i < count; i++)); do
  item_kind=$(yq ".[$i] | kind" "$input_file")

  if [[ "$item_kind" == "scalar" ]]; then
    # Entry is a filepath to a sind config
    config=$(yq ".[$i]" "$input_file")
    if [[ ! -f "$config" ]]; then
      echo "::error::Config file not found: $config"
      exit 1
    fi
    label="$config"
  elif [[ "$item_kind" == "map" ]]; then
    # Entry is an inline sind config, write to temp file
    config="${tmp_dir}/inline-${i}.yml"
    yq ".[$i]" "$input_file" > "$config"
    label="inline cluster $i"
  else
    echo "::error::Unexpected entry type at index $i: $item_kind"
    exit 1
  fi

  # Build command flags
  flags=(--config "$config" "${wait_flags[@]}")
  [[ "${SIND_PULL:-false}" == "true" ]] && flags+=(--pull)

  echo "::group::Creating cluster from $label"
  if ! sind "$SIND_VERBOSITY" create cluster "${flags[@]}"; then
    echo "::endgroup::"
    echo "::error::Failed to create cluster from $label"
    exit 1
  fi
  echo "::endgroup::"

  # Extract cluster name
  name=$(yq '.name // "default"' "$config")

  sind "$SIND_VERBOSITY" "${status_cmd[@]}" "$name"

  if [[ -n "$clusters" ]]; then
    clusters="${clusters},${name}"
  else
    clusters="$name"
  fi
done

echo "clusters=${clusters}" >> "$GITHUB_OUTPUT"
echo "Created clusters: ${clusters}"
