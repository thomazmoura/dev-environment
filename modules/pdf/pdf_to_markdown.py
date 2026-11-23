"""Prints a PDF as Markdown on stdout.

Run through pdf2md (this folder) on the venv Install-PdfTools.ps1 creates, by
pdfcat when piped and by NeoVim on opening a *.pdf (nvim-config's
lua/config/pdf.lua).

The conversion is pymupdf4llm's. On top of it, this:
- keeps the library's messages off stdout, where they'd end up in the document;
- turns its bullet indentation, the distance from the margin in characters, into
  nesting levels: four spaces or more would read as a code block;
- separates pages with a rule, and squeezes runs of blank lines;
- drops control characters, since a PDF's text is printed to a terminal and
  could otherwise carry escape sequences.
"""

import contextlib
import io
import os
import re
import signal
import sys

CONTROL = re.compile(r"[\x00-\x08\x0b-\x1f\x7f-\x9f\ud800-\udfff]")
BULLET = re.compile(r"^( *)- ")


def fail(message):
    sys.exit("pdf2md: " + CONTROL.sub("", message))


def tidy(page):
    lines = []
    fenced = False
    for line in CONTROL.sub("", page).split("\n"):
        if line.startswith("```"):
            fenced = not fenced
        lines.append((line, fenced))

    indents = {len(m[1]) for line, code in lines if not code and (m := BULLET.match(line))}
    levels = {indent: level for level, indent in enumerate(sorted(indents))}

    result = []
    for line, code in lines:
        if not code:
            line = line.rstrip()
            if not line and (not result or not result[-1]):
                continue
            if bullet := BULLET.match(line):
                line = "  " * levels[len(bullet[1])] + line[len(bullet[1]):]
        result.append(line)
    if fenced:
        result.append("```")  # or the rest of the document would read as code
    return "\n".join(result).strip("\n")


def convert(path):
    # pymupdf keeps the stdout it finds when imported, so import it in here too
    with contextlib.redirect_stdout(io.StringIO()):
        import pymupdf

        pymupdf.TOOLS.mupdf_display_errors(False)
        pymupdf.TOOLS.mupdf_display_warnings(False)
        import pymupdf4llm

        try:
            document = pymupdf.open(path)
        except Exception:
            fail(f"can't read {path} as a PDF")
        if not document.is_pdf:
            fail(f"{path} is not a PDF")
        if document.needs_pass:
            fail(f"{path} is password protected")
        try:
            chunks = pymupdf4llm.to_markdown(document, ignore_images=True, page_chunks=True)
        except Exception as error:
            fail(f"can't convert {path}: {error}")

    return [text for chunk in chunks if (text := tidy(chunk["text"]))]


def main():
    arguments = sys.argv[1:]
    if arguments[:1] == ["--"]:
        arguments = arguments[1:]
    if len(arguments) != 1:
        fail("usage: pdf2md <file.pdf>")
    path = arguments[0]
    if not os.path.isfile(path):
        fail(f"no such file: {path}")

    pages = convert(path)
    if not pages:
        fail(f"no text in {path} (a scan? those need OCR, e.g. ocrmypdf)")

    signal.signal(signal.SIGPIPE, signal.SIG_DFL)  # quiet under `| head`
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stdout.write("\n\n---\n\n".join(pages) + "\n")


if __name__ == "__main__":
    main()
