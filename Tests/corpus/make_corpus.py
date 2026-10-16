#!/usr/bin/env python3
"""Sintetik test PDF'larini yaratadi (tashqi kutubxonasiz, xref'ni o'zi hisoblaydi).

    python3 Tests/corpus/make_corpus.py

Natija shu papkaga yoziladi:
  hello.pdf    — 2 sahifa (A4 va Letter-landscape), matn va rangli shakllar
  rotated.pdf  — /Rotate 90 bilan bitta sahifa
"""

import os
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))


def pdf_string(text: str) -> bytes:
    escaped = text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")
    return ("(" + escaped + ")").encode("latin-1")


def build_pdf(pages):
    """pages: [(width, height, content_bytes, extra_page_dict_entries)]"""
    objects = []  # index i -> obj number i+1

    def add(body: bytes) -> int:
        objects.append(body)
        return len(objects)

    catalog = add(b"")  # keyin to'ldiriladi
    pages_obj = add(b"")
    font = add(b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica "
               b"/Encoding /WinAnsiEncoding >>")
    page_ids = []
    for width, height, content, extra in pages:
        data = zlib.compress(content)
        stream = add(b"<< /Length %d /Filter /FlateDecode >>\nstream\n" % len(data)
                     + data + b"\nendstream")
        page = add(b"<< /Type /Page /Parent %d 0 R /MediaBox [0 0 %g %g] "
                   b"/Resources << /Font << /F1 %d 0 R >> >> /Contents %d 0 R %s>>"
                   % (pages_obj, width, height, font, stream, extra))
        page_ids.append(page)
    objects[catalog - 1] = b"<< /Type /Catalog /Pages %d 0 R >>" % pages_obj
    kids = b" ".join(b"%d 0 R" % p for p in page_ids)
    objects[pages_obj - 1] = b"<< /Type /Pages /Kids [%s] /Count %d >>" % (kids, len(page_ids))

    out = bytearray(b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n")
    offsets = []
    for number, body in enumerate(objects, start=1):
        offsets.append(len(out))
        out += b"%d 0 obj\n" % number + body + b"\nendobj\n"
    xref = len(out)
    out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objects) + 1)
    for off in offsets:
        out += b"%010d 00000 n \n" % off
    out += (b"trailer\n<< /Size %d /Root %d 0 R /Info << /Title (UPDF Craft corpus) >> >>\n"
            b"startxref\n%d\n%%%%EOF\n" % (len(objects) + 1, catalog, xref))
    return bytes(out)


def text(x, y, size, s):
    return b"BT /F1 %g Tf %g %g Td " % (size, x, y) + pdf_string(s) + b" Tj ET\n"


def page_one():
    c = bytearray()
    c += b"0.10 0.35 0.85 rg 56 700 483 90 re f\n"          # ko'k banner
    c += b"1 1 1 rg\n" + text(76, 735, 32, "Hello, UPDF Craft")
    c += b"0 0 0 rg\n" + text(56, 650, 14, "Page one: CraftCore M0 render test.")
    c += text(56, 628, 14, "The quick brown fox jumps over the lazy dog.")
    c += b"0.90 0.20 0.20 rg 56 400 150 150 re f\n"          # qizil kvadrat
    c += b"0.15 0.70 0.30 rg 230 400 150 150 re f\n"         # yashil kvadrat
    c += b"0 0 0 RG 4 w 400 400 m 540 550 l S\n"             # qora chiziq
    return bytes(c)


def page_two():
    c = bytearray()
    c += b"0.95 0.75 0.10 rg 36 36 720 540 re f\n"
    c += b"0 0 0 rg\n" + text(72, 300, 28, "Page two (Letter landscape)")
    return bytes(c)


def rotated_page():
    c = bytearray()
    c += b"0.4 0.1 0.6 rg 50 50 200 100 re f\n"
    c += b"0 0 0 rg\n" + text(50, 300, 20, "Rotated 90")
    return bytes(c)


def main():
    files = {
        "hello.pdf": build_pdf([
            (595.276, 841.89, page_one(), b""),
            (792, 612, page_two(), b""),
        ]),
        "rotated.pdf": build_pdf([(400, 600, rotated_page(), b"/Rotate 90 ")]),
    }
    for name, data in files.items():
        with open(os.path.join(HERE, name), "wb") as f:
            f.write(data)
        print(f"{name}: {len(data)} bayt")


if __name__ == "__main__":
    main()
