"""
Format shader (or any text) files according to .editorconfig-style rules:

    indent_style = tab
    end_of_line = lf
    trim_trailing_whitespace = true
    insert_final_newline = true

Usage:
    python format_shaders.py [DIR] [EXT...] [--indent-size N]

    DIR             Root directory to scan (default: current directory)
    EXT...          File extensions to process (default: .glsl .fsh .vsh .csh .frag .vert .comp)
    --indent-size N Spaces per indent level in original files (default: 4)
"""

import os
import re
import sys


DEFAULT_EXTENSIONS = ['.glsl', '.fsh', '.vsh', '.csh', '.frag', '.vert', '.comp']


def leading_whitespace_to_tabs(line, indent_size):
    """Convert leading whitespace to tabs. Preserve intra-line alignment."""
    m = re.match(r'^([ \t]*)', line)
    if not m:
        return line
    leading = m.group(0)
    rest = line[m.end():]

    width = 0
    for ch in leading:
        if ch == '\t':
            width += indent_size
        else:
            width += 1

    num_tabs = width // indent_size
    return '\t' * num_tabs + rest


def format_file(filepath, indent_size):
    with open(filepath, 'r', encoding='utf-8', newline='') as f:
        content = f.read()

    lines = content.split('\n')

    formatted_lines = []
    for line in lines:
        line = line.rstrip(' \t\r')
        line = leading_whitespace_to_tabs(line, indent_size)
        formatted_lines.append(line)

    result = '\n'.join(formatted_lines)
    if not result.endswith('\n'):
        result += '\n'

    with open(filepath, 'w', encoding='utf-8', newline='') as f:
        f.write(result)


def main():
    args = sys.argv[1:]

    # Parse --indent-size
    indent_size = 4
    filtered = []
    for a in args:
        if a.startswith('--indent-size='):
            indent_size = int(a.split('=', 1)[1])
        elif a == '--indent-size':
            pass  # handled below
        else:
            filtered.append(a)
    args = filtered

    # Parse positional: DIR and extensions
    root = os.getcwd()
    extensions = DEFAULT_EXTENSIONS
    ext_args = []

    for a in args:
        if a.startswith('.'):
            ext_args.append(a)
        else:
            root = a

    if ext_args:
        extensions = ext_args

    # Normalize extensions
    extensions = set(e if e.startswith('.') else '.' + e for e in extensions)

    print(f'Root: {root}')
    print(f'Extensions: {", ".join(sorted(extensions))}')
    print(f'Indent size: {indent_size}')
    print()

    count = 0
    for dirpath, dirnames, filenames in os.walk(root):
        for fn in filenames:
            ext = os.path.splitext(fn)[1]
            if ext in extensions:
                filepath = os.path.join(dirpath, fn)
                format_file(filepath, indent_size)
                count += 1
                rel = os.path.relpath(filepath, root)
                print(f'  {rel}')

    print(f'\nTotal: {count} files formatted.')


if __name__ == '__main__':
    main()
