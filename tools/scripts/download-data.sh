#!/usr/bin/env bash
# Download Wiktionary data from kaikki.org
#
# Usage:
#   ./download-data.sh                    # Download English (default)
#   ./download-data.sh french             # Download French
#   ./download-data.sh --list             # List available languages
#   ./download-data.sh --sample english   # Download first 10000 lines only
#
# Data is saved to data/raw/ directory

set -euo pipefail

# Base URL for kaikki.org data
BASE_URL="https://kaikki.org/dictionary"

# Output directory
DATA_DIR="$(dirname "$0")/../../data/raw"

# Create data directory if needed
mkdir -p "$DATA_DIR"

# Available languages (most common ones)
declare -A LANGUAGES=(
    ["english"]="English/kaikki.org-dictionary-English.jsonl.gz"
    ["french"]="French/kaikki.org-dictionary-French.jsonl.gz"
    ["german"]="German/kaikki.org-dictionary-German.jsonl.gz"
    ["spanish"]="Spanish/kaikki.org-dictionary-Spanish.jsonl.gz"
    ["italian"]="Italian/kaikki.org-dictionary-Italian.jsonl.gz"
    ["portuguese"]="Portuguese/kaikki.org-dictionary-Portuguese.jsonl.gz"
    ["russian"]="Russian/kaikki.org-dictionary-Russian.jsonl.gz"
    ["chinese"]="Chinese/kaikki.org-dictionary-Chinese.jsonl.gz"
    ["japanese"]="Japanese/kaikki.org-dictionary-Japanese.jsonl.gz"
    ["korean"]="Korean/kaikki.org-dictionary-Korean.jsonl.gz"
    ["arabic"]="Arabic/kaikki.org-dictionary-Arabic.jsonl.gz"
    ["hindi"]="Hindi/kaikki.org-dictionary-Hindi.jsonl.gz"
    ["dutch"]="Dutch/kaikki.org-dictionary-Dutch.jsonl.gz"
    ["swedish"]="Swedish/kaikki.org-dictionary-Swedish.jsonl.gz"
    ["polish"]="Polish/kaikki.org-dictionary-Polish.jsonl.gz"
)

# Show usage
show_usage() {
    echo "Usage: $0 [OPTIONS] [LANGUAGE]"
    echo ""
    echo "Download Wiktionary JSONL data from kaikki.org"
    echo ""
    echo "Options:"
    echo "  --list          List available languages"
    echo "  --sample LANG   Download only first 10,000 lines (for testing)"
    echo "  --help          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                      # Download English (default)"
    echo "  $0 french               # Download French"
    echo "  $0 --sample english     # Download English sample"
    echo ""
    echo "Data will be saved to: $DATA_DIR"
}

# List available languages
list_languages() {
    echo "Available languages:"
    echo ""
    for lang in "${!LANGUAGES[@]}"; do
        printf "  %-15s %s\n" "$lang" "${LANGUAGES[$lang]}"
    done | sort
    echo ""
    echo "For more languages, see: https://kaikki.org/dictionary/rawdata.html"
}

# Download a language
download_language() {
    local lang="${1:-english}"
    local sample="${2:-false}"
    
    # Normalize language name
    lang=$(echo "$lang" | tr '[:upper:]' '[:lower:]')
    
    if [[ ! -v "LANGUAGES[$lang]" ]]; then
        echo "Error: Unknown language '$lang'"
        echo "Use --list to see available languages"
        exit 1
    fi
    
    local path="${LANGUAGES[$lang]}"
    local url="${BASE_URL}/${path}"
    local filename=$(basename "$path")
    local output_path="${DATA_DIR}/${filename}"
    
    echo "Downloading: $url"
    echo "Output: $output_path"
    echo ""
    
    if [[ "$sample" == "true" ]]; then
        local sample_path="${DATA_DIR}/${lang}-sample.jsonl"
        echo "Creating sample (first 10,000 lines)..."
        echo ""
        
        # Download, decompress, take first 10000 lines
        curl -# -L "$url" | gunzip | head -n 10000 > "$sample_path"
        
        echo ""
        echo "Sample saved to: $sample_path"
        echo "Lines: $(wc -l < "$sample_path")"
        echo "Size: $(du -h "$sample_path" | cut -f1)"
    else
        # Download with progress
        if command -v wget &> /dev/null; then
            wget --progress=bar:force -O "$output_path" "$url"
        elif command -v curl &> /dev/null; then
            curl -# -L -o "$output_path" "$url"
        else
            echo "Error: Neither wget nor curl found"
            exit 1
        fi
        
        echo ""
        echo "Downloaded to: $output_path"
        echo "Size: $(du -h "$output_path" | cut -f1)"
    fi
    
    echo ""
    echo "To process this data, run:"
    if [[ "$sample" == "true" ]]; then
        echo "  cargo run -p dict-preprocessor --release -- -i \"$sample_path\" -o \"${DATA_DIR}/${lang}-sample.db\""
    else
        echo "  cargo run -p dict-preprocessor --release -- -i \"$output_path\" -o \"${DATA_DIR}/${lang}.db\""
    fi
}

# Parse arguments
SAMPLE=false
LANGUAGE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            show_usage
            exit 0
            ;;
        --list|-l)
            list_languages
            exit 0
            ;;
        --sample|-s)
            SAMPLE=true
            if [[ $# -gt 1 && ! "$2" =~ ^- ]]; then
                LANGUAGE="$2"
                shift
            fi
            shift
            ;;
        -*)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
        *)
            LANGUAGE="$1"
            shift
            ;;
    esac
done

# Default to English
if [[ -z "$LANGUAGE" ]]; then
    LANGUAGE="english"
fi

# Run download
download_language "$LANGUAGE" "$SAMPLE"
