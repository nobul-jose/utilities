# Utilities Directory

This directory contains shell scripts and Python utilities organized by category to help with various system administration, data migration, monitoring, and document conversion tasks.

## Directory Structure

```
utilities/
├── analysis/          # Data analysis scripts
├── conversion/        # Document format conversion tools
├── migration/         # Data migration and recovery scripts
├── monitoring/        # System monitoring and alerting scripts
├── stornext/          # StorNext filesystem-specific utilities
├── system/            # System-level utilities (multipath, etc.)
└── testing/           # API and development testing scripts
```

---

## 📊 Analysis Scripts

Scripts for analyzing data, logs, and system information.

### `add_date_windows.py`
Analyzes date windows in archive files to identify missing time ranges. Examines `add_date` timestamps across multiple archive files and reports on entries within and outside specified time windows.

**Usage:**
```bash
python utilities/analysis/add_date_windows.py
```

**Purpose:** Identifies gaps in archive data by analyzing timestamp distributions across different archive files.

---

### `analyze_missing_dm_info.py`
Analyzes missing file paths and their associated dm_info (data management info) blocks. Extracts and reports on flags, cpymap, class, vsn, totvers, and stub information for missing files.

**Usage:**
```bash
python utilities/analysis/analyze_missing_dm_info.py
```

**Purpose:** Helps diagnose why certain files are missing by examining their metadata characteristics.

---

### `analyze_missing_media_stats.py`
Analyzes missing files and correlates them with media IDs, segment UUIDs, and add dates. Provides statistics on which media have the most missing files and calculates missing ratios per medium.

**Usage:**
```bash
python utilities/analysis/analyze_missing_media_stats.py
```

**Purpose:** Identifies problematic media or time periods that have high rates of missing files.

---

## 🔄 Conversion Scripts

Tools for converting documents between different formats.

### `pdf_to_markdown.py`
General-purpose PDF to Markdown converter. Extracts text from PDFs, removes page delimiters and footers, cleans up ligatures, and adds basic markdown formatting.

**Usage:**
```bash
python utilities/conversion/pdf_to_markdown.py input.pdf
python utilities/conversion/pdf_to_markdown.py input.pdf -o output.md
```

**Requirements:** `pip install pypdf`

**Purpose:** Converts PDF documents to markdown for easier editing, searching, and LLM processing.

---

### `pdf_to_man_markdown.py`
Specialized converter for PDF man pages documentation. Extracts man pages from PDFs, adds proper markdown headings for commands and sections, and creates a structured document.

**Usage:**
```bash
python utilities/conversion/pdf_to_man_markdown.py input.pdf
python utilities/conversion/pdf_to_man_markdown.py input.pdf -o output.md
```

**Requirements:** `pip install pypdf`

**Purpose:** Converts PDF man page reference guides into searchable, structured markdown documentation.

---

## 🚚 Migration Scripts

Scripts for data migration, recovery, and bulk operations.

### `rsync_from_manifest.sh`
Generates a file list from a manifest and performs rsync operations from source to destination. Supports dry-run mode and handles missing file lists.

**Usage:**
```bash
utilities/migration/rsync_from_manifest.sh
utilities/migration/rsync_from_manifest.sh --dry-run
```

**Configuration:** Edit script to set `SRC_ROOT`, `DEST_ROOT`, `MANIFEST`, `MISSING_LIST`, and `OUT_LIST` paths.

**Purpose:** Performs efficient file synchronization based on manifest files, useful for large-scale data migrations.

---

### `run_on_dirs.sh`
Executes a command template against each directory listed in a file. Uses `{}` as a placeholder for the directory path.

**Usage:**
```bash
utilities/migration/run_on_dirs.sh 'fsretrieve -R "{}"'
utilities/migration/run_on_dirs.sh 'du -sh "{}"'
utilities/migration/run_on_dirs.sh 'ls -la "{}"'
```

**Configuration:** Edit script to set `BASE_PATH` and `DIRS_FILE` paths.

**Purpose:** Batch operations on multiple directories, useful for applying commands across many paths.

---

## 📡 Monitoring Scripts

Scripts for system monitoring and alerting.

### `network_throughput_email.sh`
Generates network throughput reports using `sar` and emails them. Designed for cron job scheduling.

**Usage:**
```bash
utilities/monitoring/network_throughput_email.sh user@example.com
```

**Cron Example:**
```cron
*/10 * * * * /path/to/utilities/monitoring/network_throughput_email.sh admin@example.com
```

**Purpose:** Automated network performance monitoring with email alerts.

---

### `run_with_email.sh`
Executes a command and sends email notifications at start and completion. Captures stdout and stderr, compresses logs, and attaches them to completion email.

**Usage:**
1. Edit the script to configure:
   - `COMMAND`: The command to execute
   - `EMAIL_TO`: Recipient email address
   - `EMAIL_FROM`: Sender email address
   - `OUTPUT_DIR`: Directory for log files

2. Run the script:
```bash
utilities/monitoring/run_with_email.sh
```

**Purpose:** Long-running command monitoring with email notifications and log archiving.

---

## 💾 StorNext Scripts

Utilities specific to StorNext filesystem operations.

### `analyze_buffercache_waste.sh`
Analyzes StorNext buffer cache efficiency by examining cvdb traces. Detects wasted buffer cache reads caused by excessive `cachebuffersize` mount settings.

**Usage:**
```bash
# Set environment variables (optional)
export TRACE_DIR=/tmp/cvdb_buffer_analysis
export DURATION=60
export OUTPUT_FILE=buffercache_waste_analysis.out

# Run the script
sudo utilities/stornext/analyze_buffercache_waste.sh
```

**Purpose:** Optimizes StorNext `cachebuffersize` mount option by identifying buffer cache waste.

---

### `analyze_read_io_patterns.sh`
Analyzes StorNext read I/O patterns using cvdb and snseq. Helps troubleshoot performance issues by examining sequential vs random reads, I/O sizes, latency, and fragmentation.

**Usage:**
```bash
# Set environment variables (optional)
export PARENT_DIR=/stornext/path/to/analyze
export DURATION=60
export OUTPUT_FILE=read_io_analysis.out

# Run the script
sudo utilities/stornext/analyze_read_io_patterns.sh
```

**Purpose:** Performance troubleshooting for StorNext read operations.

---

### `clone_directory_tree.sh`
Recreates a directory tree structure with all metadata (permissions, ownership, timestamps, ACLs, extended attributes) from source to destination. Does NOT copy files - only directories and their metadata.

**Usage:**
```bash
utilities/stornext/clone_directory_tree.sh /source/dir /dest/dir
utilities/stornext/clone_directory_tree.sh -v -a -x /source/dir /dest/dir
utilities/stornext/clone_directory_tree.sh -d -v /source/dir /dest/dir  # Dry run
```

**Options:**
- `-v, --verbose`: Show detailed progress
- `-d, --dry-run`: Preview without making changes
- `-a, --acls`: Copy ACLs (requires getfacl/setfacl)
- `-x, --xattrs`: Copy extended attributes
- `-l, --log FILE`: Log output to file

**Purpose:** Preserves directory structure and metadata when migrating or backing up StorNext filesystems.

---

### `fsretrieve_to_unmanaged.sh`
Recursively retrieves files from a managed StorNext directory to an unmanaged location. Creates a copy of files in a non-managed directory, preserving directory structure.

**Usage:**
```bash
utilities/stornext/fsretrieve_to_unmanaged.sh /stornext/managed/project1 /local/backup/project1
utilities/stornext/fsretrieve_to_unmanaged.sh -v -p 8 -c 1 /stornext/managed/archive /backup/archive
```

**Options:**
- `-v, --verbose`: Show detailed progress
- `-d, --dry-run`: Preview without making changes
- `-p, --parallel N`: Number of parallel retrieve operations (default: 4)
- `-c, --copy N`: Retrieve specific copy number (1, 2, etc.)
- `-g, --glacier TYPE`: Glacier restore type: standard, expedited, bulk
- `-f, --force`: Overwrite existing files
- `-l, --log FILE`: Log output to file

**Purpose:** Extracts files from StorNext managed storage to unmanaged locations for backup or migration.

---

## ⚙️ System Scripts

System-level utilities for device management and recovery.

### `quick_reload_multipath.sh`
Quick reload of multipath device to fix `blk_cloned_rq_check_limits` errors. Minimal version that just reloads the device table.

**Usage:**
```bash
sudo utilities/system/quick_reload_multipath.sh dm-4
```

**Purpose:** Fast fix for multipath device errors without full recovery procedure.

---

### `recover_multipath_max_segment.sh`
Recovery script for multipath device `max_segment_kb` issues. Fixes "blk_cloned_rq_check_limits: over max size limit" errors by adjusting device mapper table settings.

**Usage:**
```bash
sudo utilities/system/recover_multipath_max_segment.sh
```

**Purpose:** Comprehensive recovery for multipath devices experiencing segment size limit errors.

---

### `reload_multipath_without_unmount.sh`
Reloads multipath device table without unmounting filesystems. Fixes "blk_cloned_rq_check_limits" errors by reloading the device mapper table while keeping filesystems mounted.

**Usage:**
```bash
sudo utilities/system/reload_multipath_without_unmount.sh
```

**Purpose:** Safe multipath device recovery without service interruption.

---

## 🧪 Testing Scripts

Development and API testing utilities.

### `test_anthropic_api.py`
Diagnostic script to test Anthropic API key configuration and identify issues. Checks environment variables, validates key format, and makes test API calls.

**Usage:**
```bash
export ANTHROPIC_API_KEY='your-key-here'
python utilities/testing/test_anthropic_api.py
```

**Purpose:** Validates Anthropic API key setup and troubleshoots authentication issues.

---

### `test_anthropic_direct.py`
Direct API key testing tool that prompts for a key. Useful for testing keys without setting environment variables.

**Usage:**
```bash
python utilities/testing/test_anthropic_direct.py
# Paste your API key when prompted
```

**Purpose:** Quick API key validation without environment variable setup.

---

## General Notes

### Permissions
Many scripts require root privileges, especially:
- StorNext scripts (cvdb commands)
- System scripts (multipath device management)
- Some migration scripts (file operations)

### Dependencies
Python scripts may require additional packages:
- `pypdf` - For PDF conversion scripts
- `anthropic` - For API testing scripts

Install with:
```bash
pip install pypdf anthropic
```

### Configuration
Several scripts use hardcoded paths or require environment variables. Check each script's header comments for configuration options.

### Error Handling
Most scripts include error handling and cleanup routines. Check exit codes and log files for troubleshooting.

---

## Contributing

When adding new scripts:
1. Place them in the appropriate subdirectory
2. Add documentation to this README
3. Include usage examples and requirements
4. Add proper error handling and cleanup

---

*Last updated: January 2026*
