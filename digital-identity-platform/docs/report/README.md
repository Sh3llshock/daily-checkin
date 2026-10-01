# The report

`report.md` is the assembled report: cover page, the required section headers in
order (Introduction, Architecture, Implementation, Experimental Results, Discussion &
Conclusion), every figure and table with the final numbers, the reference list and
an appendix pointer. Each yellow **WRITER** box marks text that workstream writes in
its own words, using the prompts with the same section number in
[`../report-draft.md`](../report-draft.md). Replace each box with the text.

Build the PDF:

```bash
docs/report/build.sh        # needs pandoc 3.x and xelatex (TeX Live / MacTeX)
```

It applies the coursebook format: 10pt Times New Roman, double spaced, A4, 1-inch
margins, page numbers in the footer, cover page unnumbered. Tables, captions and the
reference list are single spaced (see `header.tex`); if a TA says everything must be
double spaced, delete those lines and re-check the page count.

## Page budget: read this before writing

With only the figures, tables and empty boxes, the build is already 10 pages:
cover + **7 content pages** + references + appendix. References don't count; ask a TA
whether the cover and the appendix do. That leaves roughly **2–3 pages (about
1,000–1,300 words double spaced) for all the prose**, which isn't enough for the plan
in `report-draft.md`. Ways to make room, biggest first:

1. Shrink figures: the `{width=…}` on each image. The architecture and gatekeeper
   figures stay readable at about 60–70 %.
2. Move the interaction overview (Figure 1) to the slides only, or the gatekeeper
   flow to the appendix.
3. Keep only the report-sized test table (Table 3) in the body (already done; the
   80-row table is in the appendix pointer).
4. Merge Tables 4 and 5, or drop the bytecode column.

Run `pdfinfo report.pdf | grep Pages` after every merge.
