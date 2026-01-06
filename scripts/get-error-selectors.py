#!/usr/bin/env python3
"""
Extract error selectors from Solidity files using Foundry's cast command.
Usage: python3 scripts/get-error-selectors.py [file_path]
       python3 scripts/get-error-selectors.py  # for all files in src/
"""

import subprocess
import re
import sys
from pathlib import Path

def extract_error_signature(line):
    """Extract error signature from a Solidity error declaration line."""
    # Match: error ErrorName(type1,type2);
    match = re.match(r'\s*error\s+([^;]+);', line)
    if match:
        return match.group(1).strip()
    return None

def get_selector(error_sig):
    """Get selector for an error signature using cast sig."""
    try:
        result = subprocess.run(
            ['cast', 'sig', error_sig],
            capture_output=True,
            text=True,
            check=True
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError:
        return None

def process_file(file_path):
    """Process a single Solidity file and extract error selectors."""
    errors = []
    try:
        with open(file_path, 'r') as f:
            for line in f:
                error_sig = extract_error_signature(line)
                if error_sig:
                    selector = get_selector(error_sig)
                    if selector:
                        errors.append((selector, error_sig, file_path))
    except Exception as e:
        print(f"Error processing {file_path}: {e}", file=sys.stderr)
    return errors

def main():
    if len(sys.argv) > 1:
        # Process specific file
        file_path = Path(sys.argv[1])
        if not file_path.exists():
            print(f"Error: File {file_path} not found", file=sys.stderr)
            sys.exit(1)
        errors = process_file(file_path)
    else:
        # Process all .sol files in src/
        src_dir = Path('src')
        if not src_dir.exists():
            print("Error: src/ directory not found", file=sys.stderr)
            sys.exit(1)
        
        errors = []
        for sol_file in src_dir.rglob('*.sol'):
            errors.extend(process_file(sol_file))
    
    # Sort by selector for consistent output
    errors.sort(key=lambda x: x[0])
    
    # Print results
    print("Error Selectors:")
    print("=" * 80)
    for selector, error_sig, file_path in errors:
        rel_path = file_path.relative_to(Path.cwd()) if file_path.is_absolute() else file_path
        print(f"{selector}  {error_sig}")
        print(f"    ({rel_path})")
        print()

if __name__ == '__main__':
    main()




