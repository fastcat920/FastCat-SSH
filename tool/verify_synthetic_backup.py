"""Independently verify the public synthetic fixture; no user secrets are read."""
import base64
import hashlib
import json
from pathlib import Path
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

fixture = Path(__file__).resolve().parents[1] / 'test/fixtures/dart_v1.fastcatbackup'
envelope = json.loads(fixture.read_bytes())
field = lambda key: base64.b64decode(envelope[key])
key = hashlib.pbkdf2_hmac('sha256', 'Compatibility-only_测试 🔐 123'.encode(), field('salt'), envelope['iterations'], 32)
plaintext = AESGCM(key).decrypt(field('nonce'), field('ciphertext') + field('mac'), b'FastCat:1')
assert json.loads(plaintext)['data']['hosts'][0]['name'] == '跨端测试'
print('Public Dart fixture verified by independent Python PBKDF2/AES-GCM.')
