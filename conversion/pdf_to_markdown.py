#!/usr/bin/env python3
"""
PDF to Markdown Converter (General Purpose)

Converts any PDF document into clean, LLM-friendly markdown file with proper formatting.

This utility handles:
- PDF text extraction
- Removal of page delimiters, footers, and running headers
- Ligature and spacing cleanup
- Basic markdown formatting
"""

import re
import sys
from pathlib import Path
from typing import Optional

try:
    from pypdf import PdfReader
except ImportError:
    print("Error: pypdf is required. Install it with: pip install pypdf", file=sys.stderr)
    sys.exit(1)


class PDFToMarkdownConverter:
    """Converts PDF documents to structured markdown."""
    
    # Ligature replacements
    LIGATURE_REPLACEMENTS = {
        "ﬁ": "fi",
        "ﬂ": "fl",
        "ﬀ": "ff",
        "ﬃ": "ffi",
        "ﬄ": "ffl",
        "ﬅ": "st",
        "ﬆ": "st",
        "'": "'",
        "'": "'",
        """: '"',
        """: '"',
        "–": "-",
        "—": "-",
        "−": "-",
        "\u00A0": " ",  # non-breaking space
    }
    
    def __init__(self, pdf_path: Path):
        """Initialize converter with PDF path."""
        self.pdf_path = Path(pdf_path)
        if not self.pdf_path.exists():
            raise FileNotFoundError(f"PDF file not found: {pdf_path}")
    
    def extract_text(self) -> str:
        """Extract text from all PDF pages."""
        reader = PdfReader(str(self.pdf_path))
        lines = []
        
        for i, page in enumerate(reader.pages, start=1):
            text = page.extract_text() or ""
            # Normalize Windows-style newlines
            text = text.replace("\r\n", "\n").rstrip()
            lines.append(text)
        
        return "\n".join(lines)
    
    def remove_page_delimiters(self, text: str) -> str:
        """Remove page delimiters and markers."""
        lines = []
        for line in text.splitlines():
            stripped = line.strip()
            # Remove page delimiters
            if stripped == "---":
                continue
            # Remove page markers like <!-- Page 1 -->
            if re.match(r"<!--\s*Page\s+\d+\s*-->", stripped, re.IGNORECASE):
                continue
            lines.append(line)
        return "\n".join(lines)
    
    def remove_footers(self, text: str) -> str:
        """Remove common footer patterns."""
        lines = []
        footer_patterns = [
            re.compile(r"StorNext\s+File\s+System\s+\d+\s*$", re.IGNORECASE),
            re.compile(r"Page\s+\d+\s+of\s+\d+\s*$", re.IGNORECASE),
            re.compile(r"^\d+\s*$"),  # Standalone page numbers
        ]
        
        for line in text.splitlines():
            stripped = line.strip()
            # Skip if matches any footer pattern
            if any(p.match(stripped) for p in footer_patterns):
                continue
            lines.append(line)
        return "\n".join(lines)
    
    def remove_running_headers(self, text: str) -> str:
        """Remove document-wide running headers."""
        lines = []
        
        for line in text.splitlines():
            stripped = line.strip()
            
            # Remove common document headers (customize as needed)
            if stripped.startswith("StorNext 7 Man Pages Reference Guide"):
                continue
            if stripped.startswith("6-68799-01"):
                continue
            if stripped.startswith("December 2022"):
                continue
            
            lines.append(line)
        
        return "\n".join(lines)
    
    def cleanup_ligatures(self, text: str) -> str:
        """Replace PDF ligatures with ASCII equivalents."""
        for old, new in self.LIGATURE_REPLACEMENTS.items():
            text = text.replace(old, new)
        return text
    
    def cleanup_uppercase_spacing(self, text: str) -> str:
        """Collapse spaces within uppercase words."""
        def collapse(match):
            return match.group(0).replace(' ', '')
        
        # Pattern for uppercase words with spaces (2+ segments)
        pattern = re.compile(r'\b(?:[A-Z]{1,4}\s+){2,}[A-Z]{1,4}\b')
        text = pattern.sub(collapse, text)
        
        return text
    
    def add_basic_formatting(self, text: str) -> str:
        """Add basic markdown formatting for headings and lists."""
        lines = text.splitlines()
        out_lines = []
        
        for i, line in enumerate(lines):
            stripped = line.strip()
            
            # Skip empty lines
            if not stripped:
                out_lines.append("")
                continue
            
            # Detect potential headings (all caps, short lines)
            if (stripped.isupper() and 
                len(stripped) < 100 and 
                len(stripped.split()) <= 10 and
                not stripped.startswith("http")):
                # Check if next line is not also a heading
                if i + 1 < len(lines) and lines[i + 1].strip():
                    # Add heading markdown
                    out_lines.append(f"## {stripped}")
                    continue
            
            out_lines.append(line)
        
        return "\n".join(out_lines)
    
    def convert(self, output_path: Optional[Path] = None) -> str:
        """Convert PDF to markdown with all processing steps."""
        print(f"Extracting text from {self.pdf_path}...")
        text = self.extract_text()
        
        print("Removing page delimiters...")
        text = self.remove_page_delimiters(text)
        
        print("Removing footers...")
        text = self.remove_footers(text)
        
        print("Removing running headers...")
        text = self.remove_running_headers(text)
        
        print("Cleaning up ligatures...")
        text = self.cleanup_ligatures(text)
        
        print("Cleaning up uppercase spacing...")
        text = self.cleanup_uppercase_spacing(text)
        
        print("Adding basic formatting...")
        text = self.add_basic_formatting(text)
        
        # Write output
        if output_path is None:
            output_path = self.pdf_path.with_suffix('.md')
        
        output_path = Path(output_path)
        output_path.write_text(text + "\n", encoding="utf-8")
        
        print(f"Conversion complete! Output written to: {output_path}")
        return str(output_path)


def main():
    """Main entry point."""
    import argparse
    
    parser = argparse.ArgumentParser(
        description="Convert PDF documents to markdown",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s input.pdf
  %(prog)s input.pdf -o output.md
  %(prog)s input.pdf --output custom_name.md
        """
    )
    
    parser.add_argument(
        "pdf_path",
        type=Path,
        help="Path to input PDF file"
    )
    
    parser.add_argument(
        "-o", "--output",
        type=Path,
        default=None,
        help="Path to output markdown file (default: input filename with .md extension)"
    )
    
    args = parser.parse_args()
    
    try:
        converter = PDFToMarkdownConverter(args.pdf_path)
        converter.convert(args.output)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
