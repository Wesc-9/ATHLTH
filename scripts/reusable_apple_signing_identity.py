#!/usr/bin/env python3
"""Authenticated encrypted CI storage for one reusable Apple Distribution identity.

Only an AES-GCM envelope ever leaves the GitHub runner. The encryption key is
derived, with domain separation, from the existing ASC_API_KEY_P8 secret via
HKDF-SHA256. Use a separate dedicated repository secret in a future hardening
pass; changing the ASC key will invalidate envelopes sealed under the old key.
"""
from __future__ import annotations

import base64
import json
import os
from pathlib import Path
import re
import sys
from datetime import datetime, timedelta, timezone

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives.serialization import pkcs12

FORMAT = "athlth-apple-distribution-p12-v1"
KEY_INFO = b"ATHLTH/AppStoreConnect/CI/DistributionP12/v1"
KDF_SALT = b"ATHLTH-GitHub-Actions-signing-2026-v1"


def derive_key() -> bytes:
    key_path = Path(os.environ["ASC_KEY_PATH"])
    secret = key_path.read_bytes().strip()
    if not secret.startswith(b"-----BEGIN PRIVATE KEY-----"):
        raise ValueError("Missing or invalid App Store Connect API private key")
    return HKDF(
        algorithm=hashes.SHA256(), length=32, salt=KDF_SALT, info=KEY_INFO
    ).derive(secret)


def identity(data: bytes, password: bytes):
    private_key, cert, _ = pkcs12.load_key_and_certificates(data, password)
    if not private_key or cert is None:
        raise ValueError("P12 is missing its private key or signing certificate")
    if private_key.public_key().public_bytes(
        serialization.Encoding.DER,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    ) != cert.public_key().public_bytes(
        serialization.Encoding.DER,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    ):
        raise ValueError("P12 private key does not match the certificate")
    return cert


def certificate_id(value: str) -> str:
    if not re.fullmatch(r"[A-Z0-9]{6,32}", value):
        raise ValueError("Untrusted Apple certificate ID")
    return value


def write_secret(path: str, data: bytes) -> None:
    destination = Path(path)
    destination.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(str(destination), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
    except BaseException:
        destination.unlink(missing_ok=True)
        raise


def aad(cert_id: str) -> bytes:
    return (FORMAT + ":" + certificate_id(cert_id)).encode("ascii")


def seal(p12_path: str, password_file: str, cert_id: str, output: str) -> None:
    cert_id = certificate_id(cert_id)
    p12 = Path(p12_path).read_bytes()
    password = Path(password_file).read_bytes().strip()
    cert = identity(p12, password)
    nonce = os.urandom(12)
    payload = json.dumps({
        "p12": base64.b64encode(p12).decode("ascii"),
        "password": base64.b64encode(password).decode("ascii"),
    }, separators=(",", ":")).encode("utf-8")
    ciphertext = AESGCM(derive_key()).encrypt(nonce, payload, aad(cert_id))
    envelope = {
        "format": FORMAT, "certificate_id": cert_id,
        "certificate_sha256": cert.fingerprint(hashes.SHA256()).hex(),
        "nonce": base64.b64encode(nonce).decode("ascii"),
        "ciphertext": base64.b64encode(ciphertext).decode("ascii"),
    }
    Path(output).parent.mkdir(parents=True, exist_ok=True)
    Path(output).write_text(json.dumps(envelope, sort_keys=True) + "\n")
    os.chmod(output, 0o600)
    print("Sealed authenticated Apple Distribution identity for reuse.")


def unseal(envelope_path: str, p12_path: str, password_file: str, id_file: str) -> None:
    envelope = json.loads(Path(envelope_path).read_text())
    if envelope.get("format") != FORMAT:
        raise ValueError("Unsupported stored signing identity format")
    cert_id = certificate_id(envelope["certificate_id"])
    nonce = base64.b64decode(envelope["nonce"], validate=True)
    ciphertext = base64.b64decode(envelope["ciphertext"], validate=True)
    if len(nonce) != 12 or len(ciphertext) > 500_000:
        raise ValueError("Invalid encrypted signing envelope")
    data = AESGCM(derive_key()).decrypt(nonce, ciphertext, aad(cert_id))
    document = json.loads(data)
    p12 = base64.b64decode(document["p12"], validate=True)
    password = base64.b64decode(document["password"], validate=True)
    cert = identity(p12, password)
    if cert.fingerprint(hashes.SHA256()).hex() != envelope["certificate_sha256"]:
        raise ValueError("Stored certificate fingerprint mismatch")
    write_secret(p12_path, p12)
    write_secret(password_file, password + b"\n")
    write_secret(id_file, (cert_id + "\n").encode())
    print("Decrypted the reusable Apple signing identity in runner-private temporary files.")


def verify(
    apple_certificate_path: str, p12_path: str, password_file: str, id_file: str
) -> None:
    cert_id = certificate_id(Path(id_file).read_text().strip())
    response = json.loads(Path(apple_certificate_path).read_text())["data"]
    attributes = response["attributes"]
    if response["id"] != cert_id or attributes["certificateType"] != "DISTRIBUTION":
        raise ValueError("Apple certificate ID/type does not match stored signing identity")
    apple_cert = x509.load_der_x509_certificate(
        base64.b64decode(attributes["certificateContent"], validate=True)
    )
    local_cert = identity(
        Path(p12_path).read_bytes(),
        Path(password_file).read_bytes().strip(),
    )
    if apple_cert.fingerprint(hashes.SHA256()) != local_cert.fingerprint(hashes.SHA256()):
        raise ValueError("Stored certificate is not the active Apple signing certificate")
    expiry = local_cert.not_valid_after_utc
    now = datetime.now(timezone.utc)
    if expiry <= now + timedelta(days=30):
        raise ValueError("Apple Distribution identity is expiring in <=30 days; rotate deliberately")
    print(f"Verified reusable Apple Distribution signing identity; expires {expiry.date().isoformat()}.")


if __name__ == "__main__":
    try:
        mode, *args = sys.argv[1:]
        if mode == "seal" and len(args) == 4:
            seal(*args)
        elif mode == "unseal" and len(args) == 4:
            unseal(*args)
        elif mode == "verify" and len(args) == 4:
            verify(*args)
        else:
            raise ValueError("Usage: signing_identity.py seal|unseal|verify <four arguments>")
    except Exception as exc:
        print(f"Signing identity validation failed: {exc}", file=sys.stderr)
        sys.exit(1)
