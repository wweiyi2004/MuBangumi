"""Anonymous user ids: salted SHA-256.

The salt is generated once, stored only in the local data directory (which is
git-ignored) and never exported. The same (username, salt) always produces the
same id, so checkpoints and exported matrices stay stable across runs. Raw
usernames remain only in the git-ignored seed files and local resume database.
"""
from __future__ import annotations

import hashlib
import secrets
from pathlib import Path


def load_or_create_salt(path: Path) -> str:
    """Read the salt from disk or generate and persist a fresh one."""
    if path.exists():
        salt = path.read_text(encoding="utf-8").strip()
        if not salt:
            raise ValueError(f"salt file exists but is empty: {path}")
        return salt
    salt = secrets.token_hex(16)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(salt + "\n", encoding="utf-8")
    return salt


def anonymous_user_id(username: str, salt: str) -> str:
    """Deterministic salted hash of a username; hex digest, 64 chars."""
    material = f"{salt}:{username.strip()}"
    return hashlib.sha256(material.encode("utf-8")).hexdigest()
