#!/usr/bin/env bash
set -euo pipefail

# Write input to temp file for yq to process
input_file=$(mktemp --suffix=.yml)
echo "$SIND_CLUSTERS" > "$input_file"

# `sind status` was replaced by `sind get cluster` in sind v0.9.0.
sind_version=$(sind version --json | jq -r '.version')
if [[ "$(printf '%s\n' 0.9.0 "$sind_version" | sort -V | head -n1)" == "0.9.0" ]]; then
  status_cmd=(get cluster)
else
  status_cmd=(status)
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
    config=$(mktemp --suffix=.yml)
    yq ".[$i]" "$input_file" > "$config"
    label="inline cluster $i"
  else
    echo "::error::Unexpected entry type at index $i: $item_kind"
    exit 1
  fi

  # Build command flags
  flags=(--config "$config")
  [[ "${SIND_PULL:-false}" == "true" ]] && flags+=(--pull)

  echo "::group::Creating cluster from $label"
  sind "$SIND_VERBOSITY" create cluster "${flags[@]}"
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

rm -f "$input_file"

echo "clusters=${clusters}" >> "$GITHUB_OUTPUT"
echo "Created clusters: ${clusters}"
