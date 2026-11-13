"""Every test gets its own empty database and the standard protocol, so
tests can't see each other's data or anything on the developer's machine."""
import pytest

from app import protocol, security, store


@pytest.fixture(autouse=True)
def isolated_data(tmp_path, monkeypatch):
    for name in ("SPAI_API_KEY", "SPAI_INSTRUCTOR_PIN", "SPAI_RETENTION_DAYS"):
        monkeypatch.delenv(name, raising=False)
    store.use_store(store.Store(tmp_path / "test.db"))
    protocol.use_protocols(protocol.ProtocolStore(tmp_path / "protocol.json"))
    yield
    store.get_store().close()
    store.use_store(None)
    protocol.use_protocols(None)
