"""
Builds the step deliverables from markdown to PDF.

  python deliverables/build_pdf.py            (all steps)
  python deliverables/build_pdf.py step2      (one step)
  python deliverables/build_pdf.py report     (final report)
  python deliverables/build_pdf.py slides     (presentation)

Needs the `markdown` package and Google Chrome. Mermaid diagrams are
drawn by mermaid.js in the browser before printing.
"""

import os
import re
import subprocess
import sys
import markdown
import pymupdf as fitz  # used to add page numbers to the report

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "src")
CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"

TEMPLATE = """<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>{title}</title>
<style>
  @page {{ size: A4; margin: 2cm; }}
  body {{ font-family: "Times New Roman", serif; font-size: 11pt; line-height: 1.35; color: #000; }}
  h1 {{ font-size: 18pt; margin-bottom: 4px; }}
  h2 {{ font-size: 14pt; margin-top: 18px; border-bottom: 1px solid #999; }}
  h3 {{ font-size: 12pt; margin-top: 14px; }}
  table {{ border-collapse: collapse; width: 100%; margin: 8px 0; font-size: 9.5pt; }}
  tr {{ page-break-inside: avoid; }}
  h2, h3 {{ page-break-after: avoid; }}
  th, td {{ border: 1px solid #777; padding: 3px 6px; vertical-align: top; text-align: left; }}
  th {{ background: #e8e8e8; }}
  code {{ font-family: Consolas, monospace; font-size: 9pt; }}
  pre {{ background: #f4f4f4; padding: 6px; font-size: 8.5pt; white-space: pre-wrap; page-break-inside: avoid; }}
  pre.mermaid {{ background: none; text-align: center; }}
  .subtitle {{ color: #444; margin-top: 0; }}
</style>
<script src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"></script>
<script>mermaid.initialize({{ startOnLoad: true, theme: "neutral", securityLevel: "loose" }});</script>
</head><body>
{body}
</body></html>
"""


# Report format from the coursebook: 10pt Times New Roman, double spaced,
# A4 with 1 inch margins, numbered pages.
REPORT_CSS = """
  @page { size: A4; margin: 2.54cm; }
  body { font-family: "Times New Roman", serif; font-size: 10pt; line-height: 2; }
  h1 { font-size: 16pt; line-height: 1.3; }
  h2 { font-size: 12pt; margin-top: 14px; border-bottom: none; }
  h3 { font-size: 10.5pt; margin-top: 8px; margin-bottom: 0; }
  p, li { text-align: justify; }
  table { font-size: 8.5pt; line-height: 1.25; margin: 6px 0; }
  pre { line-height: 1.2; font-size: 8pt; }
  .cover { text-align: center; page-break-after: always; line-height: 1.5; padding-top: 25%; }
  .cover h1 { font-size: 20pt; }
  .cover p { text-align: center; }
  table { page-break-inside: avoid; }
  .fig svg { max-height: 10cm; width: auto !important; }
  .caption { text-align: center; font-size: 8.5pt; line-height: 1.3; margin-top: 0; }
  figure, .fig { text-align: center; page-break-inside: avoid; margin: 4px 0; line-height: 1; }
"""


def add_page_numbers(pdf_path, skip_first=True):
    doc = fitz.open(pdf_path)
    for i, page in enumerate(doc):
        if skip_first and i == 0:
            continue
        rect = page.rect
        page.insert_text((rect.width / 2 - 5, rect.height - 30), str(i), fontsize=9, fontname="tiro")
    doc.saveIncr()
    doc.close()


def build(name):
    md_path = os.path.join(SRC, name + ".md")
    with open(md_path, encoding="utf-8") as f:
        text = f.read()

    body = markdown.markdown(text, extensions=["tables", "fenced_code"])
    # turn ```mermaid blocks into something mermaid.js picks up
    body = re.sub(r'<pre><code class="language-mermaid">(.*?)</code></pre>',
                  r'<pre class="mermaid">\1</pre>', body, flags=re.S)

    is_report = name == "report"
    html = TEMPLATE.format(title=name, body=body)
    if is_report:
        html = html.replace("</style>", REPORT_CSS + "</style>")

    html_path = os.path.join(SRC, name + ".html")
    with open(html_path, "w", encoding="utf-8") as f:
        f.write(html)

    pdf_path = os.path.join(HERE, name + ".pdf" if is_report else name + "-deliverable.pdf")
    subprocess.run([
        CHROME, "--headless=new", "--disable-gpu", "--no-pdf-header-footer",
        "--virtual-time-budget=20000", "--print-to-pdf=" + pdf_path,
        "file:///" + html_path.replace("\\", "/"),
    ], check=True, capture_output=True)
    if is_report:
        add_page_numbers(pdf_path)
    print("built", pdf_path)


def build_slides():
    """src/slides.html -> presentation.pdf (16:9)."""
    html_path = os.path.join(SRC, "slides.html")
    pdf_path = os.path.join(HERE, "presentation.pdf")
    subprocess.run([
        CHROME, "--headless=new", "--disable-gpu", "--no-pdf-header-footer",
        "--virtual-time-budget=20000", "--print-to-pdf=" + pdf_path,
        "file:///" + html_path.replace("\\", "/"),
    ], check=True, capture_output=True)
    # mermaid adds a hidden element at the end of the page, which gives an empty last page
    doc = fitz.open(pdf_path)
    while doc.page_count > 1 and not doc[-1].get_text().strip():
        doc.delete_page(-1)
    doc.saveIncr()
    doc.close()
    print("built", pdf_path)


if __name__ == "__main__":
    names = sys.argv[1:] or sorted(f[:-3] for f in os.listdir(SRC) if re.match(r"step\d+\.md$", f))
    for n in names:
        if n == "slides":
            build_slides()
        else:
            build(n)
