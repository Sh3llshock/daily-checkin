"""
Builds presentation.pdf (16:9) from slides.html with headless Google Chrome.

  python build_slides.py

Needs Google Chrome (or set CHROME to its path), an internet connection
(the diagram is drawn by mermaid.js from a CDN) and `pip install pymupdf`.
"""

import os
import shutil
import subprocess
import sys

import pymupdf as fitz

HERE = os.path.dirname(os.path.abspath(__file__))
CHROME_PATHS = [
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "google-chrome",
    "chromium",
]


def find_chrome() -> str:
    for path in [os.environ.get("CHROME", "")] + CHROME_PATHS:
        if path and (os.path.exists(path) or shutil.which(path)):
            return path
    sys.exit("Google Chrome not found, set CHROME to its path")


def main() -> None:
    html_path = os.path.join(HERE, "slides.html")
    pdf_path = os.path.join(HERE, "presentation.pdf")
    subprocess.run([
        find_chrome(), "--headless=new", "--disable-gpu", "--no-pdf-header-footer",
        "--virtual-time-budget=20000", "--print-to-pdf=" + pdf_path,
        "file:///" + html_path.replace("\\", "/").lstrip("/"),
    ], check=True, capture_output=True)
    # mermaid adds a hidden element at the end of the page, which gives an empty last page
    doc = fitz.open(pdf_path)
    while doc.page_count > 1 and not doc[-1].get_text().strip():
        doc.delete_page(-1)
    doc.saveIncr()
    doc.close()
    print("built", pdf_path)


if __name__ == "__main__":
    main()
