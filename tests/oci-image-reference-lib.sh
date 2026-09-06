#!/usr/bin/env bash
# shellcheck disable=SC2034  # public outputs are consumed by sourcing gates
# Helpers for static gates that inspect OCI image references.
#
# oci_parse_image_reference keeps the supplied reference byte-for-byte in
# OCI_IMAGE_REFERENCE for diagnostics or re-emission. It derives a separate
# OCI_IMAGE_COMPARISON_KEY containing only the repository/name. Tags and
# digests are aliases of the same image repository and are removed for policy
# comparisons. Explicit registry ports are parsed as decimal u16 values and
# canonicalized in the comparison key, while their original spelling survives
# in OCI_IMAGE_REFERENCE.

oci_parse_image_reference() {
  local reference="$1"
  local without_digest
  local leaf
  local prefix
  local registry_component
  local registry_path_suffix
  local normalized_registry_component
  local registry_host
  local host_suffix
  local explicit_port
  local leading_zeros
  local normalized_port
  local has_explicit_port=0

  OCI_IMAGE_REFERENCE="$reference"
  OCI_IMAGE_PARSE_ERROR=""
  OCI_IMAGE_COMPARISON_KEY=""
  without_digest="${reference%%@*}"
  leaf="${without_digest##*/}"

  if [[ "$without_digest" == */* ]]; then
    prefix="${without_digest%/*}"
  else
    prefix=""
  fi

  if [[ -n "$prefix" ]]; then
    registry_component="${prefix%%/*}"
    registry_path_suffix="${prefix#"$registry_component"}"
    normalized_registry_component="$registry_component"

    if [[ "$registry_component" == \[* ]]; then
      if [[ "$registry_component" != *"]"* ]]; then
        OCI_IMAGE_PARSE_ERROR="malformed registry component '$registry_component': expected [host] or [host]:<decimal port>"
        return 2
      fi

      registry_host="${registry_component%%]*}"
      registry_host="${registry_host}]"
      host_suffix="${registry_component#*]}"
      if [[ "$registry_host" == "[]" ]]; then
        OCI_IMAGE_PARSE_ERROR="malformed registry component '$registry_component': bracketed host is empty"
        return 2
      fi

      case "$host_suffix" in
        "") ;;
        :*)
          has_explicit_port=1
          explicit_port="${host_suffix#:}"
          ;;
        *)
          OCI_IMAGE_PARSE_ERROR="malformed registry component '$registry_component': expected [host] or [host]:<decimal port>"
          return 2
          ;;
      esac
    elif [[ "$registry_component" == *"["* || "$registry_component" == *"]"* ]]; then
      OCI_IMAGE_PARSE_ERROR="malformed registry component '$registry_component': brackets must enclose the complete host"
      return 2
    elif [[ "$registry_component" == *:* ]]; then
      has_explicit_port=1
      registry_host="${registry_component%%:*}"
      explicit_port="${registry_component#*:}"
      if [[ -z "$registry_host" ]]; then
        OCI_IMAGE_PARSE_ERROR="malformed registry component '$registry_component': host before explicit port is empty"
        return 2
      fi
    fi

    if [[ "$has_explicit_port" -eq 1 ]]; then
      if [[ ! "$explicit_port" =~ ^[0-9]+$ ]]; then
        OCI_IMAGE_PARSE_ERROR="invalid explicit registry port '$explicit_port' in '$registry_component': expected a decimal integer from 1 to 65535"
        return 2
      fi

      leading_zeros="${explicit_port%%[!0]*}"
      normalized_port="${explicit_port#"$leading_zeros"}"
      [[ -n "$normalized_port" ]] || normalized_port=0

      if [[ "$normalized_port" == 0 ]] \
        || [[ "${#normalized_port}" -gt 5 ]] \
        || ((10#$normalized_port > 65535)); then
        OCI_IMAGE_PARSE_ERROR="invalid explicit registry port '$explicit_port' in '$registry_component': expected a decimal integer from 1 to 65535"
        return 2
      fi

      normalized_registry_component="${registry_host}:${normalized_port}"
    fi

    prefix="${normalized_registry_component}${registry_path_suffix}"
  fi

  # Only a colon in the final path component introduces a tag. Colons in the
  # prefix belong to an explicit registry port (or a bracketed IPv6 host).
  if [[ "$leaf" == *:* ]]; then
    leaf="${leaf%%:*}"
  fi

  if [[ -n "$prefix" ]]; then
    OCI_IMAGE_COMPARISON_KEY="${prefix}/${leaf}"
  else
    OCI_IMAGE_COMPARISON_KEY="$leaf"
  fi

  return 0
}

# Returns 0 for a generic core repository, 1 for another valid repository and
# 2 for a malformed reference that policy callers must reject.
oci_is_generic_streamline_core_image() {
  oci_parse_image_reference "$1" || return 2
  case "$OCI_IMAGE_COMPARISON_KEY" in
    streamline|*/streamline) return 0 ;;
    *) return 1 ;;
  esac
}
