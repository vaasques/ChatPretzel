#!/usr/bin/env python3
"""Development-only; the installed app has no Python dependency."""
import hashlib
import json
from pathlib import Path
import zipfile

root = Path(__file__).resolve().parents[1]
manifest = json.loads((root / "Fixtures/manifest.json").read_text())
for item in manifest:
    path = root / "Fixtures/files" / item["name"]
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    assert path.stat().st_size == item["size"], f"Size mismatch: {path.name}"
    assert digest == item["sha256"], f"Hash mismatch: {path.name}"
    if path.suffix in (".docx", ".xlsx"):
        with zipfile.ZipFile(path) as archive:
            assert archive.testzip() is None
            assert "[Content_Types].xml" in archive.namelist()
    if path.suffix == ".pdf":
        assert path.read_bytes().startswith(b"%PDF-")
    print(f"PASS-fixture-integrity: {path.name}")
print("Original fixture files verified. This does NOT verify transfer to WebKit or ChatGPT.")
