#!/usr/bin/env python3
"""Generate small, synthetic ChatDesk attachment fixtures.

All output is deliberately written below test-results/, which is ignored by git.
Existing fixture binaries are copied rather than renamed or rewritten.
"""
from __future__ import annotations

import base64
import hashlib
import json
import shutil
import subprocess
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "test-results" / "filetype-matrix"
OUT.mkdir(parents=True, exist_ok=True)

FIXTURES = ROOT / "Fixtures" / "files"
existing = {
    ".pdf": FIXTURES / "01 sample åäö.pdf",
    ".docx": FIXTURES / "02 sample åäö.docx",
    ".xlsx": FIXTURES / "03 sample åäö.xlsx",
    ".png": FIXTURES / "04 sample åäö.png",
    ".jpg": FIXTURES / "05 sample åäö.jpg",
    ".txt": FIXTURES / "06 sample åäö.txt",
}

# 1x1 transparent GIF (GIF89a), embedded so this script has no dependencies.
GIF_1X1 = base64.b64decode(
    "R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw=="
)

TEXT = "ChatDesk synthetic attachment fixture\nformat smoke test: åäö\n"
TEXT_EXTENSIONS = [".csv", ".tsv", ".md", ".json", ".html", ".xml", ".py", ".js", ".css", ".sql", ".yaml"]


def write_text(ext: str) -> None:
    contents = {
        ".csv": "name,value\nsynthetic,1\n",
        ".tsv": "name\tvalue\nsynthetic\t1\n",
        ".md": "# ChatDesk fixture\n\nSynthetic text fixture.\n",
        ".json": '{"fixture":"chatdesk","synthetic":true}\n',
        ".html": "<!doctype html><html><body>ChatDesk fixture</body></html>\n",
        ".xml": "<?xml version=\"1.0\"?><fixture synthetic=\"true\">chatdesk</fixture>\n",
        ".py": "# ChatDesk synthetic fixture\nVALUE = 1\n",
        ".js": "// ChatDesk synthetic fixture\nconst value = 1;\n",
        ".css": "/* ChatDesk synthetic fixture */\n.fixture { color: #123456; }\n",
        ".sql": "-- ChatDesk synthetic fixture\nSELECT 1 AS value;\n",
        ".yaml": "fixture: chatdesk\nsynthetic: true\n",
    }
    (OUT / ("synthetic" + ext)).write_text(contents[ext], encoding="utf-8")


def make_pptx() -> None:
    """Write a minimal, structurally valid PPTX containing one slide."""
    files = {
        "[Content_Types].xml": '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="xml" ContentType="application/xml"/><Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/><Override PartName="/ppt/slides/slide1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/></Types>''',
        "_rels/.rels": '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/></Relationships>''',
        "ppt/presentation.xml": '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:sldMasterIdLst/><p:sldIdLst><p:sldId id="256" r:id="rId1" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"/></p:sldIdLst><p:sldSz cx="12192000" cy="6858000" type="screen4x3"/></p:presentation>''',
        "ppt/_rels/presentation.xml.rels": '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide1.xml"/></Relationships>''',
        "ppt/slides/slide1.xml": '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:cSld><p:spTree><p:nvGrpSpPr/><p:grpSpPr/></p:spTree></p:cSld></p:sld>''',
    }
    with zipfile.ZipFile(OUT / "synthetic.pptx", "w", zipfile.ZIP_DEFLATED) as zf:
        for name, data in files.items():
            zf.writestr(name, data)


def main() -> None:
    for ext, source in existing.items():
        shutil.copyfile(source, OUT / ("synthetic" + ext))
    # JPEG and JPG are the same valid JPEG payload, exposed under both common
    # extensions because clients may advertise either separately.
    shutil.copyfile(existing[".jpg"], OUT / "synthetic.jpeg")
    for ext in TEXT_EXTENSIONS:
        write_text(ext)
    (OUT / "synthetic.gif").write_bytes(GIF_1X1)
    make_pptx()

    # Convert the real XLSX through LibreOffice to produce an actual BIFF8 XLS.
    with tempfile.TemporaryDirectory() as td:
        source = Path(td) / "source.xlsx"
        shutil.copyfile(existing[".xlsx"], source)
        subprocess.run(["soffice", "--headless", "--convert-to", "xls", "--outdir", td, str(source)], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        generated = Path(td) / "source.xls"
        if not generated.exists():
            raise RuntimeError("LibreOffice did not produce source.xls")
        shutil.copyfile(generated, OUT / "synthetic.xls")

    manifest = []
    for path in sorted(OUT.iterdir()):
        if path.name == "manifest.json":
            continue
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        manifest.append({"name": path.name, "size": path.stat().st_size, "sha256": digest})
    (OUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(OUT), "count": len(manifest), "extensions": sorted(p.suffix.lower() for p in OUT.iterdir() if p.is_file() and p.name != "manifest.json")}, ensure_ascii=False))


if __name__ == "__main__":
    main()
