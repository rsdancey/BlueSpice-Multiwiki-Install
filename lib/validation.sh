#!/bin/bash

# Input validation functions for BlueSpice MediaWiki deployment
# Provides consistent validation with clear error messages

set -euo pipefail

# Validate wiki name format
validate_wiki_name() {
    local name="$1"
    
    if [[ -z "$name" ]]; then
        echo "❌ Wiki name cannot be empty" >&2
        return 1
    fi
    
    if [[ ! "$name" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        echo "❌ Wiki name must contain only alphanumeric characters, dots, dashes, and underscores" >&2
        echo "   Current value: '$name'" >&2
        return 1
    fi
    
    if [[ ${#name} -gt 50 ]]; then
        echo "❌ Wiki name must be 50 characters or less" >&2
        return 1
    fi
    
    return 0
}

# Validate domain name format
validate_domain() {
    local domain="$1"
    
    if [[ -z "$domain" ]]; then
        echo "❌ Domain name cannot be empty" >&2
        return 1
    fi
    
    if [[ ! "$domain" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        echo "❌ Invalid domain format. Expected format: subdomain.domain.tld" >&2
        echo "   Examples: wiki.example.com, docs.mysite.org" >&2
        echo "   Current value: '$domain'" >&2
        return 1
    fi
    
    return 0
}

# SMTP host validation function
validate_smtp_host() {
    local host="$1"
    
    if [[ -z "$host" ]]; then
        echo "❌ SMTP host cannot be empty" >&2
        return 1
    fi
    
    # Check if host follows basic hostname format
    if [[ ! "$host" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?))*$ ]]; then
        echo "❌ Invalid SMTP host format" >&2
        echo "   Expected format: smtp.domain.com" >&2
        echo "   Current value: '$host'" >&2
        return 1
    fi
    
    # Check if host contains at least one dot (domain format)
    if [[ ! "$host" =~ \. ]]; then
        echo "❌ SMTP host must be a fully qualified domain name" >&2
        echo "   Examples: smtp.gmail.com, mail.company.com" >&2
        return 1
    fi
    
    return 0
}

# SMTP password validation function
validate_smtp_pass() {
    local password="$1"
    
    if [[ -z "$password" ]]; then
        echo "❌ SMTP password cannot be empty" >&2
        return 1
    fi
    
    # Check if password contains spaces
    if [[ "$password" =~ [[:space:]] ]]; then
        echo "❌ SMTP password cannot contain spaces" >&2
        return 1
    fi
    
    return 0
}

# Validate email address format
validate_email() {
    local email="$1"
    
    if [[ -z "$email" ]]; then
        echo "❌ Email address cannot be empty" >&2
        return 1
    fi
    
    if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        echo "❌ Invalid email format" >&2
        echo "   Expected format: user@domain.com" >&2
        echo "   Current value: '$email'" >&2
        return 1
    fi
    
    return 0
}

# Validate file path exists
validate_file_exists() {
    local file_path="$1"
    local description="${2:-File}"
    
    if [[ -z "$file_path" ]]; then
        echo "❌ $description path cannot be empty" >&2
        return 1
    fi
    
    if [[ ! -f "$file_path" ]]; then
        echo "❌ $description not found: $file_path" >&2
        return 1
    fi
    
    if [[ ! -r "$file_path" ]]; then
        echo "❌ $description is not readable: $file_path" >&2
        return 1
    fi
    
    return 0
}

# Validate directory path
validate_port() {
    local port="$1"
    local description="${2:-Port}"
    
    if [[ -z "$port" ]]; then
        echo "❌ $description cannot be empty" >&2
        return 1
    fi
    
    if [[ ! "$port" =~ ^[0-9]+$ ]]; then
        echo "❌ $description must be a number" >&2
        echo "   Current value: '$port'" >&2
        return 1
    fi
    
    if [[ $port -lt 1 || $port -gt 65535 ]]; then
        echo "❌ $description must be between 1 and 65535" >&2
        echo "   Current value: $port" >&2
        return 1
    fi
    
    return 0
}

# Validate language code
validate_language_code() {
    local lang="$1"
    local valid_languages=("en" "de" "fr" "es" "it" "pt" "nl" "pl" "ru" "ja" "zh")
    
    if [[ -z "$lang" ]]; then
        echo "❌ Language code cannot be empty" >&2
        return 1
    fi
    
    for valid_lang in "${valid_languages[@]}"; do
        if [[ "$lang" == "$valid_lang" ]]; then
            return 0
        fi
    done
    
    echo "❌ Invalid language code: $lang" >&2
    echo "   Valid options: ${valid_languages[*]}" >&2
    return 1
}
