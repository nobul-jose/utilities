#!/usr/bin/env python3
"""
PDF to Man Pages Markdown Converter

Converts a PDF containing man pages documentation into a clean, LLM-friendly
markdown file with proper headings and formatting.

This utility handles:
- PDF text extraction
- Removal of page delimiters, footers, and running headers
- Extraction of table of contents and man pages
- Addition of markdown headings for commands and sections
- Ligature and spacing cleanup
"""

import re
import sys
from pathlib import Path
from typing import Dict, Tuple, List, Optional

try:
    from pypdf import PdfReader
except ImportError:
    print("Error: pypdf is required. Install it with: pip install pypdf", file=sys.stderr)
    sys.exit(1)


class PDFManPageConverter:
    """Converts PDF man pages to structured markdown."""
    
    # Ligature replacements
    LIGATURE_REPLACEMENTS = {
        "ﬁ": "fi",
        "ﬂ": "fl",
        "ﬀ": "ff",
        "ﬃ": "ffi",
        "ﬄ": "ffl",
        "ﬅ": "st",
        "ﬆ": "st",
        "’": "'",
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
        """Remove footer lines like 'StorNext File System 103'."""
        lines = []
        for line in text.splitlines():
            # Remove footers matching pattern: "StorNext File System <number>"
            if re.match(r"StorNext\s+File\s+System\s+\d+\s*$", line, re.IGNORECASE):
                continue
            lines.append(line)
        return "\n".join(lines)
    
    def remove_running_headers(self, text: str) -> str:
        """Remove document-wide and per-command running headers."""
        lines = []
        
        # Patterns for running headers (but keep the ones we need for detection)
        header_patterns = [
            re.compile(r"^[A-Z0-9_]+\(\d+\)\s+.*\s+[A-Z0-9_]+\(\d+\)\s*$"),  # e.g. MOUNT_CVFS(8) ... MOUNT_CVFS(8)
        ]
        
        for line in text.splitlines():
            stripped = line.strip()
            
            # Remove document-wide running headers
            if stripped.startswith("StorNext 7 Man Pages Reference Guide"):
                continue
            if stripped.startswith("6-68799-01"):
                continue
            if stripped.startswith("December 2022"):
                continue
            
            # Remove command-level running headers (but keep () pattern for detection)
            if any(p.match(stripped) for p in header_patterns):
                continue
            
            lines.append(line)
        
        return "\n".join(lines)
    
    def remove_man_page_headers(self, text: str) -> str:
        """Remove redundant man page header lines like 'AC CESS_JSON() A CCESS_JSON()'."""
        lines = []
        header_pattern = re.compile(r"^[A-Z0-9_\s]+\(\)\s+[A-Z0-9_\s]+\(\)\s*$")
        
        for line in text.splitlines():
            stripped = line.strip()
            # Remove these header lines that appear after we've already added markdown headings
            if header_pattern.match(stripped):
                continue
            lines.append(line)
        
        return "\n".join(lines)
    
    def extract_toc_and_man_pages(self, text: str) -> Tuple[str, str]:
        """Extract table of contents and man pages sections."""
        lines = text.splitlines()
        
        # Find start of Table of Contents
        toc_start = None
        for i, line in enumerate(lines):
            if line.strip() == "Table of Contents":
                toc_start = i
                break
        
        if toc_start is None:
            raise ValueError("Could not find 'Table of Contents' in source file")
        
        # Find first man-page header (like ACCESS_JSON() ACCESS_JSON())
        header_re = re.compile(r"^[A-Z0-9_ ]+\(\)\s+[A-Z0-9_ ]+\(\)\s*$")
        first_header_idx = None
        for i in range(toc_start, len(lines)):
            if header_re.match(lines[i].strip()):
                first_header_idx = i
                break
        
        if first_header_idx is None:
            raise ValueError("Could not find first man-page header in source file")
        
        # Split into TOC and man pages
        toc_block = lines[toc_start:first_header_idx]
        man_block = lines[first_header_idx:]
        
        return "\n".join(toc_block), "\n".join(man_block)
    
    def build_toc_map(self, toc_text: str) -> Dict[str, Tuple[str, str]]:
        """Build a map of normalized command names to (display_name, section)."""
        toc_map = {}
        
        def normalize(name: str) -> str:
            return re.sub(r"\s+", "", name).lower()
        
        toc_entry_re = re.compile(r"^(.+?)\s+\((\d+|[lL])\s*\)\s+\d+\s*$")
        
        for line in toc_text.splitlines():
            m = toc_entry_re.match(line.strip())
            if m:
                name, section = m.group(1).strip(), m.group(2)
                toc_map[normalize(name)] = (name, section)
        
        return toc_map
    
    def add_command_headings(self, man_text: str, toc_map: Dict[str, Tuple[str, str]]) -> str:
        """Add markdown headings (##) before each man page."""
        lines = man_text.splitlines()
        out_lines = []
        
        # Pattern for man-page header lines
        header_re = re.compile(r"^[A-Z0-9_ ]+\(\)\s+[A-Z0-9_ ]+\(\)\s*$")
        
        # Pattern for NAME section label (handles PDF spacing like 'NA ME')
        name_label_re = re.compile(r"^N\s*A\s*M\s*E\s*$", re.IGNORECASE)
        
        def normalize(name: str) -> str:
            return re.sub(r"\s+", "", name).lower()
        
        i = 0
        while i < len(lines):
            line = lines[i]
            stripped = line.strip()
            
            if header_re.match(stripped):
                # Look ahead to find NAME section and command name
                cmd_name = None
                j = i + 1
                search_limit = min(len(lines), i + 40)
                
                # Find NAME label
                while j < search_limit and not name_label_re.match(lines[j].strip()):
                    j += 1
                
                if j < search_limit and name_label_re.match(lines[j].strip()):
                    k = j + 1
                    # Next non-empty line after NAME should contain 'cmd - description'
                    while k < search_limit and lines[k].strip() == "":
                        k += 1
                    if k < search_limit:
                        name_line = lines[k].strip()
                        # Split on dash/hyphen/en-dash to get command name
                        parts = re.split(r"[\-\u2010-\u2015]", name_line, maxsplit=1)
                        cmd_name = parts[0].strip()
                
                # Determine heading text
                heading = None
                if cmd_name:
                    key = normalize(cmd_name)
                    display, section = toc_map.get(key, (cmd_name, None))
                    if section:
                        heading = f"## {display} ({section})"
                    else:
                        heading = f"## {display}"
                else:
                    # Fallback: derive from header line
                    token = stripped.split("(")[0].strip().lower()
                    heading = f"## {token}" if token else "## Command"
                
                # Ensure blank line before heading
                if out_lines and out_lines[-1].strip() != "":
                    out_lines.append("")
                out_lines.append(heading)
                out_lines.append("")
                
                # Output the original header line
                out_lines.append(line)
                i += 1
            else:
                out_lines.append(line)
                i += 1
        
        return "\n".join(out_lines)
    
    def add_section_headings(self, text: str) -> str:
        """Add markdown subheadings (###) for uppercase section labels."""
        lines = text.splitlines()
        
        # Find first command heading
        first_section_idx = None
        for idx, line in enumerate(lines):
            if line.startswith("## "):
                first_section_idx = idx
                break
        
        if first_section_idx is None:
            return text  # No command headings found, return as-is
        
        section_re = re.compile(r"^[A-Z0-9\s/_-]+$")
        
        def normalize_label(text: str) -> str:
            """Normalize section labels by collapsing spaces."""
            tokens = text.split()
            if tokens and all(len(token) <= 2 for token in tokens):
                # Likely split letters like "NA ME" -> "NAME"
                normalized = ''.join(tokens)
            else:
                normalized = ' '.join(tokens)
            return normalized
        
        out_lines = []
        for idx, line in enumerate(lines):
            stripped = line.strip()
            
            # Only process lines after first command heading
            if idx >= first_section_idx and section_re.match(stripped):
                # Check if it's all uppercase (likely a section header)
                letters = re.sub(r"[^A-Z0-9]+", "", stripped)
                if letters and letters.isupper() and len(letters) >= 2:
                    label = normalize_label(stripped)
                    heading = f"### {label}"
                    
                    # Ensure blank line before heading
                    if out_lines and out_lines[-1].strip() != "":
                        out_lines.append("")
                    out_lines.append(heading)
                    continue
            
            out_lines.append(line)
        
        return "\n".join(out_lines)
    
    def fix_missing_command_headings(self, text: str, toc_map: Dict[str, Tuple[str, str]]) -> str:
        """Ensure every NAME section has a command heading before it."""
        lines = text.splitlines()
        out_lines = []
        
        def normalize(name: str) -> str:
            return re.sub(r"\s+", "", name).lower()
        
        name_label_re = re.compile(r"^N\s*A\s*M\s*E\s*$", re.IGNORECASE)
        
        for idx, line in enumerate(lines):
            stripped = line.strip()
            
            if stripped == "### NAME":
                # Check if previous non-empty line is a command heading
                # Look back through output lines (skip blank lines)
                j = len(out_lines) - 1
                while j >= 0 and out_lines[j].strip() == "":
                    j -= 1
                
                need_heading = True
                # Check if we already have a command heading
                if j >= 0 and out_lines[j].startswith("## "):
                    need_heading = False
                else:
                    # Also check recent input lines for a heading
                    for check_idx in range(max(0, idx - 10), idx):
                        if check_idx < len(lines):
                            check_line = lines[check_idx].strip()
                            if check_line.startswith("## ") and not check_line.startswith("###"):
                                need_heading = False
                                break
                
                if need_heading:
                    # Get command name from next non-empty line(s)
                    k = idx + 1
                    while k < len(lines) and lines[k].strip() == "":
                        k += 1
                    
                    if k < len(lines):
                        name_line = lines[k].strip()
                        # Split on dash/hyphen/en dash
                        parts = re.split(r"\s*[\-\u2010-\u2015]\s*", name_line, maxsplit=1)
                        command_name = parts[0].strip()
                    else:
                        command_name = "Command"
                    
                    display, section = toc_map.get(normalize(command_name), (command_name, None))
                    heading = f"## {display} ({section})" if section else f"## {display}"
                    
                    if out_lines and out_lines[-1].strip() != "":
                        out_lines.append("")
                    out_lines.append(heading)
                    out_lines.append("")
                
                out_lines.append(line)
            else:
                out_lines.append(line)
        
        return "\n".join(out_lines)
    
    def cleanup_ligatures(self, text: str) -> str:
        """Replace PDF ligatures with ASCII equivalents."""
        for old, new in self.LIGATURE_REPLACEMENTS.items():
            text = text.replace(old, new)
        return text
    
    def cleanup_uppercase_spacing(self, text: str) -> str:
        """Collapse spaces within uppercase words."""
        # Collapse spaces within long uppercase sequences (3+ segments)
        def collapse(match):
            return match.group(0).replace(' ', '')
        
        # Pattern for uppercase words with spaces (2+ segments)
        pattern = re.compile(r'\b(?:[A-Z]{1,4}\s+){2,}[A-Z]{1,4}\b')
        text = pattern.sub(collapse, text)
        
        return text
    
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
        
        print("Extracting TOC and man pages...")
        toc_text, man_text = self.extract_toc_and_man_pages(text)
        
        print("Building TOC map...")
        toc_map = self.build_toc_map(toc_text)
        
        print("Adding command headings...")
        man_text = self.add_command_headings(man_text, toc_map)
        
        print("Adding section headings...")
        man_text = self.add_section_headings(man_text)
        
        print("Fixing missing command headings...")
        man_text = self.fix_missing_command_headings(man_text, toc_map)
        
        print("Removing redundant man page headers...")
        man_text = self.remove_man_page_headers(man_text)
        
        print("Cleaning up ligatures...")
        man_text = self.cleanup_ligatures(man_text)
        toc_text = self.cleanup_ligatures(toc_text)
        
        print("Cleaning up uppercase spacing...")
        man_text = self.cleanup_uppercase_spacing(man_text)
        toc_text = self.cleanup_uppercase_spacing(toc_text)
        
        # Combine TOC and man pages
        final_text = f"{toc_text}\n\n{man_text}\n"
        
        # Write output
        if output_path is None:
            output_path = self.pdf_path.with_suffix('.md')
        
        output_path = Path(output_path)
        output_path.write_text(final_text, encoding="utf-8")
        
        print(f"Conversion complete! Output written to: {output_path}")
        return str(output_path)


def main():
    """Main entry point."""
    import argparse
    
    parser = argparse.ArgumentParser(
        description="Convert PDF man pages to structured markdown",
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
        converter = PDFManPageConverter(args.pdf_path)
        converter.convert(args.output)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
