"""Offline security/regression tests for reusable CI signing material."""
import base64
from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import tempfile
import unittest

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID

from scripts import reusable_apple_signing_identity as signing


class ReusableAppleSigningTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        old_path = os.environ.get("ASC_KEY_PATH")
        self.addCleanup(self._restore_env, old_path)
        api_key = ec.generate_private_key(ec.SECP256R1())
        self.api_key_file = self.root / "AuthKey_fake.p8"
        self.api_key_file.write_bytes(api_key.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        ))
        os.environ["ASC_KEY_PATH"] = str(self.api_key_file)

        private_key = ec.generate_private_key(ec.SECP256R1())
        self.cert = (
            x509.CertificateBuilder()
            .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "ATHLTH CI Test")]))
            .issuer_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "ATHLTH CI Test")]))
            .public_key(private_key.public_key())
            .serial_number(x509.random_serial_number())
            .not_valid_before(datetime.now(timezone.utc) - timedelta(days=1))
            .not_valid_after(datetime.now(timezone.utc) + timedelta(days=365))
            .sign(private_key, hashes.SHA256())
        )
        self.password = b"test-only-password"
        self.p12 = self.root / "created.p12"
        self.p12.write_bytes(pkcs12.serialize_key_and_certificates(
            name=b"ATHLTH CI Test",
            key=private_key,
            cert=self.cert,
            cas=None,
            encryption_algorithm=serialization.BestAvailableEncryption(self.password),
        ))
        self.password_file = self.root / "password"
        self.password_file.write_bytes(self.password + b"\n")
        self.envelope = self.root / "signing-envelope.json"
        self.cert_id = "9SPQDF8X2J"

    @staticmethod
    def _restore_env(old_path):
        if old_path is None:
            os.environ.pop("ASC_KEY_PATH", None)
        else:
            os.environ["ASC_KEY_PATH"] = old_path

    def seal(self):
        signing.seal(
            str(self.p12), str(self.password_file), self.cert_id,
            str(self.envelope),
        )

    def unseal(self):
        output = self.root / "restored.p12"
        password = self.root / "restored.password"
        cert_id = self.root / "restored.id"
        signing.unseal(
            str(self.envelope), str(output), str(password), str(cert_id)
        )
        return output, password, cert_id

    def apple_json(self):
        path = self.root / "apple-response.json"
        path.write_text(json.dumps({"data": {
            "id": self.cert_id,
            "attributes": {
                "certificateType": "DISTRIBUTION",
                "certificateContent": base64.b64encode(
                    self.cert.public_bytes(serialization.Encoding.DER)
                ).decode("ascii"),
            },
        }}))
        return path

    def test_encrypted_artifact_roundtrips_and_matches_apple(self):
        self.seal()
        envelope = self.envelope.read_text()
        self.assertNotIn(self.password.decode(), envelope)
        self.assertNotIn("BEGIN PRIVATE KEY", envelope)
        output, password, cert_id = self.unseal()
        self.assertEqual(output.read_bytes(), self.p12.read_bytes())
        self.assertEqual(password.read_bytes().strip(), self.password)
        self.assertEqual(cert_id.read_text().strip(), self.cert_id)
        signing.verify(
            str(self.apple_json()), str(output), str(password), str(cert_id)
        )

    def test_ciphertext_tampering_is_rejected(self):
        self.seal()
        envelope = json.loads(self.envelope.read_text())
        ciphertext = bytearray(base64.b64decode(envelope["ciphertext"]))
        ciphertext[len(ciphertext) // 2] ^= 0x01
        envelope["ciphertext"] = base64.b64encode(ciphertext).decode()
        self.envelope.write_text(json.dumps(envelope))
        with self.assertRaises(Exception):
            self.unseal()

    def test_certificate_id_tampering_is_rejected(self):
        self.seal()
        envelope = json.loads(self.envelope.read_text())
        envelope["certificate_id"] = "ZZZZZZZZZZ"
        self.envelope.write_text(json.dumps(envelope))
        with self.assertRaises(Exception):
            self.unseal()

    def test_different_asc_key_cannot_decrypt(self):
        self.seal()
        different = ec.generate_private_key(ec.SECP256R1())
        self.api_key_file.write_bytes(different.private_bytes(
            serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        ))
        with self.assertRaises(Exception):
            self.unseal()

    def test_wrong_apple_certificate_is_rejected(self):
        self.seal()
        output, password, cert_id = self.unseal()
        response = self.apple_json()
        data = json.loads(response.read_text())
        data["data"]["id"] = "DIFFERENT1"
        response.write_text(json.dumps(data))
        with self.assertRaises(ValueError):
            signing.verify(str(response), str(output), str(password), str(cert_id))

    def test_invalid_certificate_id_rejected(self):
        with self.assertRaises(ValueError):
            signing.certificate_id("../../untrusted")


if __name__ == "__main__":
    unittest.main()
