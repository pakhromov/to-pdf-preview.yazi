# to-pdf-preview.yazi

A Yazi previewer plugin that renders PDF files and any file that can be converted to PDF (using external tools like LibreOffice or Pandoc) with a page counter and supports scrolling through pages.

https://github.com/user-attachments/assets/5c205ef3-d81e-4861-ab08-9fcb4a2d3e93

## Dependencies

- `pdfinfo` - for page count (`pacman -S poppler`)
- `pdftoppm` - for rendering pages to images (`pacman -S poppler`)
- A conversion tool for each non-PDF format you want to support (e.g. LibreOffice, Pandoc)

## Installation

**Via ya pkg:**
```bash
ya pkg add pakhromov/to-pdf-preview
```

**Manual:**
```bash
git clone https://github.com/pakhromov/to-pdf-preview.yazi ~/.config/yazi/plugins/to-pdf-preview.yazi
```

## Configuration

Add to `~/.config/yazi/yazi.toml`. The conversion command receives the input file as `$1` and must write the resulting PDF to `$OUTDIR`.

### Native PDF

```toml
[[plugin.prepend_previewers]]
mime = "application/pdf"
run = "to-pdf-preview"
```

### Office documents (LibreOffice)

```toml
[[plugin.prepend_previewers]]
url = "*.docx"
run = 'to-pdf-preview -- libreoffice --headless --convert-to pdf --outdir "$OUTDIR" "$1"'

[[plugin.prepend_previewers]]
url = "*.pptx"
run = 'to-pdf-preview -- libreoffice --headless --convert-to pdf --outdir "$OUTDIR" "$1"'

[[plugin.prepend_previewers]]
url = "*.odp"
run = 'to-pdf-preview -- libreoffice --headless --convert-to pdf --outdir "$OUTDIR" "$1"'

[[plugin.prepend_previewers]]
url = "*.odt"
run = 'to-pdf-preview -- libreoffice --headless --convert-to pdf --outdir "$OUTDIR" "$1"'
```

### Markdown / HTML (Pandoc)

```toml
[[plugin.prepend_previewers]]
mime = "text/markdown"
run = 'to-pdf-preview -- pandoc "$1" -o "${OUTDIR}$(basename "$1" | sed "s/\.[^.]*$/.pdf/")"'

[[plugin.prepend_previewers]]
mime = "text/html"
run = 'to-pdf-preview -- pandoc "$1" -o "${OUTDIR}$(basename "$1" | sed "s/\.[^.]*$/.pdf/")"'
```

## Usage

Scroll up/down in the preview pane to navigate pages.
