"""Le script de migration refuse les migrations destructives."""

import types

from scripts.migrate import is_destructive


class FakeRevision:
    def __init__(self, module: types.ModuleType) -> None:
        self.module = module


def _module(source: str) -> types.ModuleType:
    module = types.ModuleType("fake_revision")
    exec(source, module.__dict__)  # noqa: S102 - code de test contrôlé
    return module


def test_additive_migration_is_allowed(monkeypatch) -> None:  # type: ignore[no-untyped-def]
    module = _module("destructive = False\ndef upgrade():\n    op.add_column('jobs', None)\n")
    monkeypatch.setattr(
        "inspect.getsource", lambda fn: "def upgrade():\n    op.add_column('jobs', None)\n"
    )
    assert not is_destructive(FakeRevision(module))  # type: ignore[arg-type]


def test_drop_is_detected(monkeypatch) -> None:  # type: ignore[no-untyped-def]
    module = _module("def upgrade():\n    pass\n")
    monkeypatch.setattr(
        "inspect.getsource", lambda fn: "def upgrade():\n    op.drop_column('jobs', 'title')\n"
    )
    assert is_destructive(FakeRevision(module))  # type: ignore[arg-type]


def test_explicit_flag_is_respected() -> None:
    module = _module("destructive = True\ndef upgrade():\n    pass\n")
    assert is_destructive(FakeRevision(module))  # type: ignore[arg-type]


def test_initial_migration_is_not_destructive() -> None:
    from alembic.config import Config
    from alembic.script import ScriptDirectory

    from scripts.migrate import ROOT

    scripts = ScriptDirectory.from_config(Config(str(ROOT / "alembic.ini")))
    for revision in scripts.walk_revisions():
        assert not is_destructive(revision), revision.revision
