#!/bin/bash

# Self-signed certificate support for non-public / internal domains.
#
# Let's Encrypt cannot validate reserved or private TLDs (RFC 6761/6762 — e.g.
# .local, .internal, .lan, .test). For wikis on such domains, acme-companion
# silently fails to issue a certificate, so nginx-proxy never creates an HTTPS
# server block and HTTPS appears "broken" while HTTP works fine.
#
# For these domains we instead generate a self-signed certificate and place it
# in ${DATA_DIR}/proxy/certs/<domain>.{crt,key}, which nginx-proxy serves
# directly (independently of acme-companion).

set -euo pipefail

# Return 0 if the domain's TLD is one Let's Encrypt cannot issue certs for.
is_nonpublic_domain() {
    local domain="$1"
    local tld="${domain##*.}"
    case "${tld,,}" in
        local|localhost|internal|lan|home|corp|intranet|test|example|invalid|private)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Generate a self-signed certificate for $domain into $certs_dir as
# <domain>.crt / <domain>.key. Idempotent callers should check for an existing
# cert first. Returns non-zero on failure.
generate_self_signed_cert() {
    local domain="$1"
    local certs_dir="$2"

    if ! command -v openssl >/dev/null 2>&1; then
        log_error "openssl not found; cannot generate self-signed certificate for ${domain}"
        return 1
    fi

    if [[ ! -d "$certs_dir" ]]; then
        sudo mkdir -p "$certs_dir" 2>/dev/null || mkdir -p "$certs_dir" || {
            log_error "Could not create certificate directory: ${certs_dir}"
            return 1
        }
    fi

    local tmp_dir
    tmp_dir=$(mktemp -d)
    local tmp_crt="${tmp_dir}/cert.crt"
    local tmp_key="${tmp_dir}/cert.key"

    # 10-year validity: there is no renewal mechanism for self-signed certs here.
    # A subjectAltName is required — modern browsers ignore the CN field.
    if ! openssl req -x509 -newkey rsa:2048 -nodes \
            -keyout "$tmp_key" -out "$tmp_crt" \
            -days 3650 \
            -subj "/CN=${domain}" \
            -addext "subjectAltName=DNS:${domain}" >/dev/null 2>&1; then
        log_error "Failed to generate self-signed certificate for ${domain}"
        rm -rf "$tmp_dir"
        return 1
    fi

    local dest_crt="${certs_dir}/${domain}.crt"
    local dest_key="${certs_dir}/${domain}.key"
    local ok=true

    if [[ -w "$certs_dir" ]]; then
        install -m 0644 "$tmp_crt" "$dest_crt" && install -m 0600 "$tmp_key" "$dest_key" || ok=false
    elif command -v sudo >/dev/null 2>&1; then
        sudo install -m 0644 "$tmp_crt" "$dest_crt" && sudo install -m 0600 "$tmp_key" "$dest_key" || ok=false
    else
        ok=false
    fi

    rm -rf "$tmp_dir"

    if [[ "$ok" != true ]]; then
        log_error "Failed to install self-signed certificate into ${certs_dir}"
        return 1
    fi

    log_info "Generated self-signed certificate for ${domain} in ${certs_dir}"
    return 0
}
