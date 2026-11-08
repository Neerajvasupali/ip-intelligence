#!/usr/bin/env python3
"""Validate a Supabase backend key and save it in n8n without displaying it."""
import getpass
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

HELPER = Path.home() / '.codex/skills/n8n-credentials/scripts/credentials.py'
URL = 'https://bbrozdepnbeyavsajblj.supabase.co'

def main():
    if not sys.stdin.isatty():
        print('Run this command in your terminal; secret input is hidden.')
        return 1
    schema = subprocess.run([sys.executable, str(HELPER), 'get-schema', '--type', 'httpTemplatedCustomAuth'], capture_output=True)
    if schema.returncode:
        print('n8n API connection failed. Reconfigure the n8n-credentials skill first.')
        return 1
    secret = getpass.getpass('Supabase backend secret API key (hidden): ').strip()
    if not secret.startswith(('sb_secret_', 'eyJ')):
        print('Enter a backend secret key or legacy service_role JWT, not a publishable key.')
        return 1
    headers = {'apikey': secret}
    if secret.startswith('eyJ'):
        headers['Authorization'] = 'Bearer ' + secret
    request = urllib.request.Request(URL + '/rest/v1/rpc/ipintel_api', method='POST',
        headers={**headers, 'Content-Type': 'application/json'},
        data=json.dumps({'action': 'metrics', 'payload': {}}).encode())
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            result = json.load(response)
        if not isinstance(result, dict) or 'providers' not in result:
            raise ValueError()
    except urllib.error.HTTPError as exc:
        status = exc.code
        exc.close()
        hints = {
            401: 'Key was rejected. Check that it belongs to this project and has not expired or been revoked.',
            403: 'Access denied. Use a backend secret key or legacy service_role key.',
            404: 'API function was not found. Check the project URL and database migration.',
            429: 'Supabase rate limit reached. Retry later.',
        }
        print('Supabase returned HTTP %s. %s No credential created.' % (
            status, hints.get(status, 'Database/API error; report this status for investigation.')))
        return 1
    except (urllib.error.URLError, TimeoutError, OSError):
        print('Network connection failed. Check connectivity to the Supabase project. No credential created.')
        return 1
    except (ValueError, TypeError):
        print('Supabase returned an unexpected response. No credential created.')
        return 1
    print('Supabase connection verified.')
    fd, path = tempfile.mkstemp(prefix='supabase-credential-', suffix='.json')
    try:
        with os.fdopen(fd, 'w') as handle:
            json.dump({'template': json.dumps({'headers': headers})}, handle)
        return subprocess.run([sys.executable, str(HELPER), 'create', '--name',
            'IP Intel - Supabase backend', '--type', 'httpTemplatedCustomAuth', '--data-file', path]).returncode
    finally:
        os.unlink(path)

if __name__ == '__main__':
    sys.exit(main())
