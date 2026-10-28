#!/usr/bin/env python3
"""Build docs/Filament_Falcon_Updates_and_Quick_Start.pdf from updates_quick_start.md (WeasyPrint).
Only this short document; the project book has its own builder (docs/book/build_book.py).
    python3 docs/updates/build_updates_pdf.py"""
import os, markdown
from weasyprint import HTML

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "Filament_Falcon_Updates_and_Quick_Start.pdf")
md = open(os.path.join(HERE, "updates_quick_start.md"), encoding="utf-8").read()
body = markdown.markdown(md, extensions=["fenced_code", "tables", "md_in_html"])
html = f'<!doctype html><html><head><meta charset="utf-8"><title>The Filament Falcon: Updates and Quick Start</title>' \
       f'<link rel="stylesheet" href="updates.css"></head><body>{body}</body></html>'
HTML(string=html, base_url=HERE).write_pdf(OUT)
print("wrote", os.path.normpath(OUT))
