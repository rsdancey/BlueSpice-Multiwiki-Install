#!/usr/bin/env python3
"""
Add a tmpfs entry to the wiki-web service in a docker-compose file.
Usage: add_tmpfs.py <compose_file> <tmpfs_entry>
  e.g. add_tmpfs.py docker-compose.main.yml /tmp/wiki:uid=1002,gid=1002
"""
import re, sys

compose_file, tmpfs_entry = sys.argv[1], sys.argv[2]
tmpfs_line = f'      - {tmpfs_entry}\n'

with open(compose_file, 'r') as f:
    lines = f.readlines()

new_lines = []
in_tmpfs = False
added = 0

for i, line in enumerate(lines):
    stripped = line.rstrip('\n')

    if re.match(r'^    tmpfs:\s*$', stripped):
        in_tmpfs = True
        new_lines.append(line)
        continue

    if in_tmpfs:
        if line.startswith('      ') and line.strip().startswith('- '):
            new_lines.append(line)
            next_line = lines[i+1] if i+1 < len(lines) else ''
            if not (next_line.startswith('      ') and next_line.strip().startswith('- ')):
                new_lines.append(tmpfs_line)
                added += 1
                in_tmpfs = False
            continue
        else:
            # Empty tmpfs: block
            new_lines.append(tmpfs_line)
            added += 1
            in_tmpfs = False

    new_lines.append(line)

if in_tmpfs:
    new_lines.append(tmpfs_line)
    added += 1

if added == 0:
    # No tmpfs block found — insert one before the first volumes: block (wiki-web)
    new_lines2 = []
    found_volumes = False
    for line in new_lines:
        if not found_volumes and re.match(r'^    volumes:\s*$', line.rstrip('\n')):
            new_lines2.append('    tmpfs:\n')
            new_lines2.append(tmpfs_line)
            found_volumes = True
            added += 1
        new_lines2.append(line)
    new_lines = new_lines2

if added == 0:
    print('WARNING: Could not find tmpfs or volumes block', file=sys.stderr)
    sys.exit(1)

with open(compose_file, 'w') as f:
    f.writelines(new_lines)

print(f'Added tmpfs entry ({added} occurrence(s))')
