#!/bin/sh
# Render PiTerm-spec.pdf from the published one-pager.
#
#   tools/mkpdf.sh                 rebuild PiTerm-spec.pdf in the repo root
#
# The PDF is a headless-Chrome print of the PiTerm Artifact, which is how the
# first one was made (its metadata still says Skia/PDF). It went stale because
# nothing rebuilt it when the page changed, so this exists to make that one
# command rather than a remembered ritual.
#
# tools/piterm-print.html is the artifact's own markup with a print stylesheet
# appended: A4, backgrounds forced on, the two-column table grid collapsed to
# one - side by side each table gets ~85mm on A4 and a monospace cell wraps
# four words to a line - and page breaks kept out of the middle of a table or
# a finding.
#
# TWO FLAGS THAT ARE NOT OPTIONAL:
#   --no-pdf-header-footer   without it Chrome stamps the date and the page
#                            title across the top of every page. The older
#                            --print-to-pdf-no-header is accepted and IGNORED
#                            under --headless=new, which is how a dated header
#                            got into a render on 2026-08-28.
#   --virtual-time-budget    the page pulls three families from Google Fonts;
#                            without it the render can start before they land
#                            and fall back to Arial silently.
set -e
here=$(cd "$(dirname "$0")/.." && pwd)
out="$here/PiTerm-spec.pdf"

google-chrome --headless=new --disable-gpu --no-sandbox \
    --virtual-time-budget=20000 --no-pdf-header-footer \
    --print-to-pdf="$out" "file://$here/tools/piterm-print.html"

# Prove the fonts actually loaded. A silent fallback to Arial is the failure
# this is most likely to have, and it does not look like an error.
if command -v pdffonts >/dev/null && ! pdffonts "$out" | grep -q SairaCondensed; then
    echo "mkpdf: WARNING - Saira Condensed is not embedded; fonts did not load" >&2
fi
command -v pdfinfo >/dev/null && pdfinfo "$out" | grep -E "^(Title|Pages)"
echo "mkpdf: $out"
