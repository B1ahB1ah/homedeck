#!/usr/bin/env python3
"""Reuse a private local signing identity; never put its configuration in the repo."""
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys

app = sys.argv[1]
config = Path.home() / 'Library/Application Support/HomeDeckSigning/identity.json'
identity = os.environ.get('HOMEDECK_SIGN_IDENTITY')
if identity:
    subprocess.run(['codesign', '--force', '--sign', identity, app], check=True)
elif config.exists():
    if config.stat().st_mode & 0o077:
        raise SystemExit('Local signing configuration must have permissions 0600.')
    credentials = json.loads(config.read_text())
    original = shlex.split(subprocess.check_output(
        ['security', 'list-keychains', '-d', 'user'], text=True))
    try:
        # codesign also needs the certificate in its chain search list.
        try:
            subprocess.run(['security', 'unlock-keychain', '-p', credentials['password'],
                            credentials['keychain']], check=True, capture_output=True)
        except subprocess.CalledProcessError:
            raise SystemExit('Could not unlock the dedicated signing keychain.') from None
        subprocess.run(['security', 'list-keychains', '-d', 'user', '-s',
                        *original, credentials['keychain']], check=True)
        subprocess.run(['codesign', '--force', '--sign', credentials['identity'],
                        '--keychain', credentials['keychain'], app], check=True)
    finally:
        subprocess.run(['security', 'list-keychains', '-d', 'user', '-s', *original], check=True)
else:
    print('No persistent signing identity: using ad-hoc; updates may ask for Keychain access again.')
    subprocess.run(['codesign', '--force', '--sign', '-', app], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', app], check=True)
