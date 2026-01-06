#!/bin/bash

# Script to extract all error selectors from Solidity files in src/
# Usage: ./scripts/get-error-selectors.sh [file_path]

if [ -z "$1" ]; then
    # Extract all errors from src/ folder
    echo "Extracting error selectors from all files in src/..."
    echo ""
    
    # Find all .sol files and extract error definitions
    find src -name "*.sol" -type f | while read file; do
        # Extract error definitions from each file
        grep -h "^[[:space:]]*error[[:space:]]" "$file" | while read error_line; do
            # Extract error name and parameters (preserve spaces in parameters)
            error_sig=$(echo "$error_line" | sed -E 's/^[[:space:]]*error[[:space:]]+([^;]+);.*/\1/' | sed 's/[[:space:]]*$//')
            
            if [ ! -z "$error_sig" ]; then
                # Get selector using cast
                selector=$(cast sig "$error_sig" 2>/dev/null)
                if [ ! -z "$selector" ]; then
                    echo "$selector $error_sig ($file)"
                fi
            fi
        done
    done | sort -u
else
    # Extract errors from specific file
    file="$1"
    echo "Extracting error selectors from $file..."
    echo ""
    
    grep -h "^[[:space:]]*error[[:space:]]" "$file" | while read error_line; do
        error_sig=$(echo "$error_line" | sed -E 's/^[[:space:]]*error[[:space:]]+([^;]+);.*/\1/' | sed 's/[[:space:]]*$//')
        
        if [ ! -z "$error_sig" ]; then
            selector=$(cast sig "$error_sig" 2>/dev/null)
            if [ ! -z "$selector" ]; then
                echo "$selector $error_sig"
            fi
        fi
    done
fi

