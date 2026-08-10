"""Shared pytest setup for the _nix_options test suite.

Puts the parent `scripts/` directory on sys.path so tests can import
`_nix_options` directly. Keeps each test file free of boilerplate.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
