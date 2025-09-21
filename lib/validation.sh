#!/bin/bash

# Input validation functions for BlueSpice MediaWiki deployment
# Provides consistent validation with clear error messages

set -euo pipefail

# Validate wiki name format
validate_wiki_name() {
    local name="$1"
    
    if [[ -z "$name" ]]; then
        log_error "❌ Wiki name cannot be empty" >&2
        return 1
    fi
    
    if [[ ! "$name" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        log_error "❌ Wiki name must contain only alphanumeric characters, dots, dashes, and underscores" >&2
        log_error "   Current value: '$name'" >&2
        return 1
    fi
    
    if [[ ${#name} -gt 50 ]]; then
        log_error "❌ Wiki name must be 50 characters or less" >&2
        return 1
    fi
    
    return 0
}

# Validate domain name format
validate_domain() {
    local domain="$1"
    
    if [[ -z "$domain" ]]; then
        log_error "❌ Domain name cannot be empty" >&2
        return 1
    fi
    
    if [[ ! "$domain" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        log_error "❌ Invalid domain format. Expected format: subdomain.domain.tld" >&2
        log_error "   Current value: '$domain'" >&2
        return 1
    fi
    
    return 0
}

# SMTP host validation function
validate_smtp_host() {
    local host="$1"
    
    if [[ -z "$host" ]]; then
        log_error "❌ SMTP host cannot be empty" >&2
        return 1
    fi
    
    # Check if host follows basic hostname format
    if [[ ! "$host" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?))*$ ]]; then
        log_error "❌ Invalid SMTP host format" >&2
        log_error "   Current value: '$host'" >&2
        return 1
    fi
    
    # Check if host contains at least one dot (domain format)
    if [[ ! "$host" =~ \. ]]; then
        log_error "❌ SMTP host must be a fully qualified domain name" >&2
        return 1
    fi
    
    return 0
}

# SMTP password validation function
validate_smtp_pass() {
    local password="$1"
    
    if [[ -z "$password" ]]; then
        log_error "❌ SMTP password cannot be empty" >&2
        return 1
    fi
    
    # Check if password contains spaces
    if [[ "$password" =~ [[:space:]] ]]; then
        log_error "❌ SMTP password cannot contain spaces" >&2
        return 1
    fi
    
    return 0
}

# Validate email address format
validate_email() {
    local email="$1"
    
    if [[ -z "$email" ]]; then
        log_error "❌ Email address cannot be empty" >&2
        return 1
    fi
    
    if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        log_error "❌ Invalid email format" >&2
        log_error "   Current value: '$email'" >&2
        return 1
    fi
    
    return 0
}

# Validate file path exists
validate_file_exists() {
    local file_path="$1"
    local description="${2:-File}"
    
    if [[ -z "$file_path" ]]; then
        log_error "❌ $description path cannot be empty" >&2
        return 1
    fi
    
    if [[ ! -f "$file_path" ]]; then
        log_error "❌ $description not found: $file_path" >&2
        return 1
    fi
    
    if [[ ! -r "$file_path" ]]; then
        log_error "❌ $description is not readable: $file_path" >&2
        return 1
    fi
    
    return 0
}

# Validate directory path
validate_port() {
    local port="$1"
    local description="${2:-Port}"
    
    if [[ -z "$port" ]]; then
        log_error "❌ $description cannot be empty" >&2
        return 1
    fi
    
    if [[ ! "$port" =~ ^[0-9]+$ ]]; then
        log_error "❌ $description must be a number" >&2
        log_error "   Current value: '$port'" >&2
        return 1
    fi
    
    if [[ $port -lt 1 || $port -gt 65535 ]]; then
        log_error "❌ $description must be between 1 and 65535" >&2
        log_error "   Current value: $port" >&2
        return 1
    fi
    
    return 0
}

# Validate language code
validate_language_code() {
    local lang="$1"
    local valid_languages=("en" "de" "fr" "es" "it" "pt" "nl" "pl" "ru" "ja" "zh")
    
    if [[ -z "$lang" ]]; then
        log_error "❌ Language code cannot be empty" >&2
        return 1
    fi
    
    for valid_lang in "${valid_languages[@]}"; do
        if [[ "$lang" == "$valid_lang" ]]; then
            return 0
        fi
    done
  
    log_error "❌ Invalid language code: $lang" >&2
    log_error "   Valid options: ${valid_languages[*]}" >&2
    return 1
}
