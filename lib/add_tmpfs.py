#!/usr/bin/env python3
"""
Add a tmpfs entry to a service in a docker-compose file.
Usage: add_tmpfs.py <compose_file> <tmpfs_entry> [--service <service_name>]
  e.g. add_tmpfs.py docker-compose.main.yml /tmp/wiki:uid=1002,gid=1002
  e.g. add_tmpfs.py docker-compose.main.yml /tmp/wiki:uid=1002,gid=1002 --service wiki-task

If --service is given, only that service's block is modified.
Otherwise all services are considered. Idempotent: exits cleanly
if the entry is already present.
"""
import re, sys

def parse_args():
    args = sys.argv[1:]
    compose_file = args[0]
    tmpfs_entry = args[1]
    service_name = None
    if '--service' in args:
        idx = args.index('--service')
        if idx + 1 < len(args):
            service_name = args[idx + 1]
        else:
            print('ERROR: --service requires a value', file=sys.stderr)
            sys.exit(1)
    return compose_file, tmpfs_entry, service_name

compose_file, tmpfs_entry, target_service = parse_args()
tmpfs_line = f'      - {tmpfs_entry}\n'
target_stripped = tmpfs_line.strip()

with open(compose_file, 'r') as f:
    lines = f.readlines()

# Track which service block the cursor is in
current_service = None
in_services = False
in_tmpfs = False
added = 0
entry_exists = False  # persists across blocks — did we see the entry anywhere relevant?
block_has_entry = False  # per-block — does the current tmpfs block already have it?

new_lines = []
for i, line in enumerate(lines):
    stripped = line.rstrip('\n')

    # Detect top-level 'services:' key
    if re.match(r'^services:\s*$', stripped):
        in_services = True
        new_lines.append(line)
        continue

    # Detect service name (2-space indented key under services:)
    if in_services and re.match(r'^  \w[\w-]*:\s*$', stripped):
        current_service = stripped.strip().rstrip(':')

    # Detect end of services block (any non-indented, non-empty line)
    if in_services and stripped and not stripped.startswith(' ') and not re.match(r'^services:\s*$', stripped):
        in_services = False
        current_service = None

    # Only process tmpfs blocks in the target service (or all if no target)
    service_matches = (target_service is None or current_service == target_service)

    if service_matches and re.match(r'^    tmpfs:\s*$', stripped):
        in_tmpfs = True
        block_has_entry = False
        new_lines.append(line)
        continue

    if in_tmpfs:
        if line.startswith('      ') and line.strip().startswith('- '):
            if line.strip() == target_stripped:
                block_has_entry = True
                entry_exists = True
            new_lines.append(line)
            next_line = lines[i+1] if i+1 < len(lines) else ''
            if not (next_line.startswith('      ') and next_line.strip().startswith('- ')):
                # End of tmpfs entries — add if not already present in this block
                if not block_has_entry:
                    new_lines.append(tmpfs_line)
                    added += 1
                in_tmpfs = False
            continue
        else:
            # Empty tmpfs: block — add the entry
            new_lines.append(tmpfs_line)
            added += 1
            in_tmpfs = False

    new_lines.append(line)

if in_tmpfs:
    if not block_has_entry:
        new_lines.append(tmpfs_line)
        added += 1

# If no tmpfs block found for the target service, insert one before its volumes: block
if added == 0 and not entry_exists:
    new_lines2 = []
    current_service2 = None
    in_services2 = False
    found = False
    for line in new_lines:
        stripped2 = line.rstrip('\n')
        if re.match(r'^services:\s*$', stripped2):
            in_services2 = True
        if in_services2 and re.match(r'^  \w[\w-]*:\s*$', stripped2):
            current_service2 = stripped2.strip().rstrip(':')
        if in_services2 and stripped2 and not stripped2.startswith(' ') and not re.match(r'^services:\s*$', stripped2):
            in_services2 = False
            current_service2 = None

        svc_match = (target_service is None or current_service2 == target_service)
        if not found and svc_match and re.match(r'^    volumes:\s*$', stripped2):
            new_lines2.append('    tmpfs:\n')
            new_lines2.append(tmpfs_line)
            found = True
            added += 1
        new_lines2.append(line)
    new_lines = new_lines2

if added == 0 and not entry_exists:
    print('WARNING: Could not find tmpfs or volumes block', file=sys.stderr)
    sys.exit(1)

with open(compose_file, 'w') as f:
    f.writelines(new_lines)

if entry_exists and added == 0:
    print('tmpfs entry already present - no changes made')
else:
    print(f'Added tmpfs entry ({added} occurrence(s))')
