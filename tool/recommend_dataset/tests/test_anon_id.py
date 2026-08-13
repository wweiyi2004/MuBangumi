"""Anonymous user id: stability, salt handling, no username leakage."""
from __future__ import annotations

import pytest

from src import anon_id


def test_stable_with_same_salt(tmp_path):
    salt_path = tmp_path / "salt.txt"
    salt = anon_id.load_or_create_salt(salt_path)
    first = anon_id.anonymous_user_id("sai", salt)
    second = anon_id.anonymous_user_id("sai", salt)
    assert first == second
    assert first == anon_id.anonymous_user_id("  sai  ", salt)  # whitespace tolerant


def test_different_salt_different_id(tmp_path):
    salt_a = anon_id.load_or_create_salt(tmp_path / "a.txt")
    salt_b = anon_id.load_or_create_salt(tmp_path / "b.txt")
    assert salt_a != salt_b
    assert anon_id.anonymous_user_id("sai", salt_a) != anon_id.anonymous_user_id("sai", salt_b)


def test_id_format_and_no_username_leak():
    salt = "deadbeef" * 4
    uid = anon_id.anonymous_user_id("some_username", salt)
    assert len(uid) == 64
    assert all(c in "0123456789abcdef" for c in uid)
    assert "some_username" not in uid


def test_salt_created_and_persisted(tmp_path):
    salt_path = tmp_path / "nested" / "salt.txt"
    salt = anon_id.load_or_create_salt(salt_path)
    assert salt_path.exists()
    assert anon_id.load_or_create_salt(salt_path) == salt


def test_empty_salt_file_raises(tmp_path):
    salt_path = tmp_path / "salt.txt"
    salt_path.write_text("   \n", encoding="utf-8")
    with pytest.raises(ValueError):
        anon_id.load_or_create_salt(salt_path)
