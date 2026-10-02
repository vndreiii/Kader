#!/usr/bin/env python3
"""Create and sign the update manifest for a Kader release.

    make_manifest.py --version 1.2.0 --notes notes.md \
        --appimage dist/Kader-1.2.0-x86_64.AppImage \
        --arch dist/kader-1:1.2.0-1-x86_64.pkg.tar.zst \
        --key signing-key.pem --out dist/

Writes `kader-update.json` and `kader-update.json.sig` (base64 Ed25519
signature of the exact JSON bytes). The app refuses any manifest whose
signature does not verify against packaging/release-signing.pub, and any
download whose SHA-256 differs from the manifest. Signing uses the openssl
CLI (OpenSSL 3), so no Python packages are needed.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path


def asset(path: str | None) -> dict | None:
    if not path:
        return None
    p = Path(path)
    h = hashlib.sha256()
    with p.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return {"name": p.name, "size": p.stat().st_size, "sha256": h.hexdigest()}


def sign(data: bytes, key: str) -> bytes:
    with tempfile.NamedTemporaryFile() as msg, tempfile.NamedTemporaryFile() as sig:
        msg.write(data)
        msg.flush()
        subprocess.run(["openssl", "pkeyutl", "-sign", "-rawin", "-inkey", key,
                        "-in", msg.name, "-out", sig.name], check=True)
        return Path(sig.name).read_bytes()


def verify(data: bytes, signature: bytes, pubkey_b64: str) -> None:
    """Self-check against the public key the app ships with."""
    raw = base64.b64decode(pubkey_b64)
    der = bytes.fromhex("302a300506032b6570032100") + raw  # SubjectPublicKeyInfo for Ed25519
    with tempfile.NamedTemporaryFile() as pub, tempfile.NamedTemporaryFile() as msg, \
            tempfile.NamedTemporaryFile() as sig:
        pub.write(der); pub.flush()
        msg.write(data); msg.flush()
        sig.write(signature); sig.flush()
        subprocess.run(["openssl", "pkeyutl", "-verify", "-rawin", "-pubin", "-keyform", "DER",
                        "-inkey", pub.name, "-in", msg.name, "-sigfile", sig.name],
                       check=True, stdout=subprocess.DEVNULL)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--version", required=True)
    ap.add_argument("--tag")
    ap.add_argument("--notes", help="markdown file with the release notes")
    ap.add_argument("--appimage")
    ap.add_argument("--arch")
    ap.add_argument("--key", required=True, help="Ed25519 private key (PEM)")
    ap.add_argument("--pubkey", default=str(Path(__file__).resolve().parents[1] / "release-signing.pub"))
    ap.add_argument("--out", default=".")
    a = ap.parse_args()

    assets = {k: v for k, v in (("appimage", asset(a.appimage)), ("arch", asset(a.arch))) if v}
    manifest = {
        "version": a.version.lstrip("v"),
        "tag": a.tag or "v" + a.version.lstrip("v"),
        "date": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "notes": Path(a.notes).read_text(encoding="utf-8") if a.notes else "",
        "assets": assets,
    }
    data = json.dumps(manifest, indent=2, ensure_ascii=False).encode("utf-8") + b"\n"
    signature = sign(data, a.key)
    verify(data, signature, Path(a.pubkey).read_text().strip())

    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    (out / "kader-update.json").write_bytes(data)
    (out / "kader-update.json.sig").write_text(base64.b64encode(signature).decode() + "\n")
    print(f"signed manifest for {manifest['version']} with {', '.join(assets) or 'no'} assets", file=sys.stderr)


if __name__ == "__main__":
    main()
