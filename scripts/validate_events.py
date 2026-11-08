#!/usr/bin/env python3
"""Offline, bounded event-file preview. Does not persist or enrich events."""
import argparse
import datetime as dt
import ipaddress
import json
from pathlib import Path

MAX_BYTES = 262144
MAX_EVENTS = 100
FIELDS = {'source', 'event_id', 'occurred_at', 'event_type', 'source_ip', 'asset_id', 'account', 'outcome'}

def preview(raw):
    if len(raw) > MAX_BYTES:
        raise ValueError('File exceeds 256 KiB')
    data = json.loads(raw)
    if not isinstance(data, dict) or data.get('schema_version') != '1.0':
        raise ValueError('schema_version must be 1.0')
    events = data.get('events')
    if not isinstance(events, list) or not 1 <= len(events) <= MAX_EVENTS:
        raise ValueError('events must contain 1–100 records')
    rows, seen = [], {}
    for index, event in enumerate(events):
        errors = []
        if not isinstance(event, dict):
            rows.append({'index': index, 'status': 'rejected', 'errors': ['Record must be an object']})
            continue
        if set(event) - FIELDS:
            errors.append('Unknown event fields')
        for field in ['source', 'event_id', 'asset_id']:
            value = event.get(field)
            if not isinstance(value, str) or not value.strip() or len(value) > 150:
                errors.append(field + ': required string, maximum 150 characters')
        if event.get('event_type') != 'ssh_authentication':
            errors.append('event_type: expected ssh_authentication')
        if event.get('outcome') not in ('success', 'failure'):
            errors.append('outcome: expected success or failure')
        if 'account' in event and (not isinstance(event['account'], str) or len(event['account']) > 150):
            errors.append('account: maximum 150 characters')
        try:
            stamp = dt.datetime.fromisoformat(event['occurred_at'].replace('Z', '+00:00'))
            if stamp.tzinfo is None or stamp.utcoffset() != dt.timedelta(0):
                raise ValueError()
        except (KeyError, ValueError, TypeError, AttributeError):
            errors.append('occurred_at: expected UTC ISO 8601 timestamp')
        try:
            ipaddress.ip_address(event.get('source_ip', ''))
        except (ValueError, TypeError):
            errors.append('source_ip: invalid IP address')
        status = 'rejected' if errors else 'accepted'
        if not errors:
            key = (event['source'], event['event_id'])
            if key in seen:
                status = 'duplicate' if seen[key] == event else 'rejected'
                if status == 'rejected':
                    errors.append('Event ID conflicts with another record')
            else:
                seen[key] = event
        rows.append({'index': index, 'status': status, 'errors': errors})
    return {'preview_only': True, 'rows': rows, 'can_import': all(r['status'] != 'rejected' for r in rows)}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('file', type=Path)
    args = parser.parse_args()
    try:
        with args.file.open('rb') as handle:
            result = preview(handle.read(MAX_BYTES + 1))
        print(json.dumps(result, indent=2))
        return 0 if result['can_import'] else 1
    except (ValueError, OSError) as error:
        parser.exit(2, str(error) + '\n')

if __name__ == '__main__':
    raise SystemExit(main())
