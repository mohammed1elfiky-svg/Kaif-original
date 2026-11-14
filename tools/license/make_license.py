#!/usr/bin/env python3
"""Makes an activation key for Al-Kaif Al-Asli.

    python3 make_license.py --key kaif-license-private.pem --licensee "اسم الشركة" --expires 2027-12-31
    python3 make_license.py --key kaif-license-private.pem --licensee "اسم الشركة" --expires never

The private key must stay with the vendor only (never in the repository). The matching public key is in
src/main/java/mycompany/license/LicenseVerifier.java. Needs: pip install cryptography
"""
import argparse
import base64
import datetime
import sys

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode().rstrip('=')


def main():
    ap = argparse.ArgumentParser(description='Al-Kaif Al-Asli activation key')
    ap.add_argument('--key', required=True, help='private key (PEM)')
    ap.add_argument('--licensee', required=True, help='company name')
    ap.add_argument('--expires', default='never', help='yyyy-mm-dd or never')
    ap.add_argument('--users', default='', help='number of users (optional)')
    a = ap.parse_args()

    if a.expires != 'never':
        datetime.date.fromisoformat(a.expires)
    for v in (a.licensee, a.users):
        if ';' in v or '=' in v:
            sys.exit('";" and "=" are not allowed in the values')

    fields = [('licensee', a.licensee), ('expires', a.expires)]
    if a.users:
        fields.append(('users', a.users))
    payload = ';'.join(f'{k}={v}' for k, v in fields).encode('utf-8')

    with open(a.key, 'rb') as f:
        private_key = serialization.load_pem_private_key(f.read(), password=None)
    signature = private_key.sign(payload, padding.PKCS1v15(), hashes.SHA256())
    print(f'KAIF1.{b64url(payload)}.{b64url(signature)}')


if __name__ == '__main__':
    main()
