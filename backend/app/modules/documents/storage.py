"""Stockage des fichiers (CV, lettres, photos).

`StorageService` est une interface : le reste du code ne sait pas OÙ sont stockés
les fichiers. Aujourd'hui : `LocalStorageService` (dossier STORAGE_PATH).
Pour passer à S3 / MinIO plus tard :
1. créer `S3StorageService(StorageService)` qui implémente les 4 méthodes ;
2. ajouter "s3" à STORAGE_BACKEND dans core/config.py ;
3. le retourner dans `get_storage()`.
"""

import shutil
from abc import ABC, abstractmethod
from collections.abc import Iterator
from functools import lru_cache
from pathlib import Path
from typing import BinaryIO

from app.core.config import get_settings

CHUNK_SIZE = 64 * 1024


class StorageService(ABC):
    """Interface commune à tous les stockages de fichiers."""

    @abstractmethod
    def save(self, key: str, stream: BinaryIO) -> None:
        """Enregistre le contenu de `stream` sous la clé `key` (ex: "<user_id>/<uuid>.pdf")."""

    @abstractmethod
    def iter_chunks(self, key: str) -> Iterator[bytes]:
        """Lit le fichier par morceaux (pour une réponse HTTP en streaming)."""

    @abstractmethod
    def read_bytes(self, key: str) -> bytes:
        """Lit tout le fichier (pièces jointes d'email)."""

    @abstractmethod
    def delete(self, key: str) -> None:
        """Supprime le fichier (sans erreur s'il n'existe pas)."""

    @abstractmethod
    def exists(self, key: str) -> bool: ...


class LocalStorageService(StorageService):
    """Stockage sur le disque local (volume Docker "storage_data" en production)."""

    def __init__(self, base_path: str | Path) -> None:
        self.base_path = Path(base_path).resolve()
        self.base_path.mkdir(parents=True, exist_ok=True)

    def _path(self, key: str) -> Path:
        path = (self.base_path / key).resolve()
        # Protection contre "../../etc/passwd" : le fichier doit rester dans base_path.
        if not path.is_relative_to(self.base_path):
            raise ValueError("Invalid storage key")
        return path

    def save(self, key: str, stream: BinaryIO) -> None:
        path = self._path(key)
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("wb") as destination:
            shutil.copyfileobj(stream, destination, CHUNK_SIZE)

    def iter_chunks(self, key: str) -> Iterator[bytes]:
        with self._path(key).open("rb") as source:
            while chunk := source.read(CHUNK_SIZE):
                yield chunk

    def read_bytes(self, key: str) -> bytes:
        return self._path(key).read_bytes()

    def delete(self, key: str) -> None:
        self._path(key).unlink(missing_ok=True)

    def exists(self, key: str) -> bool:
        return self._path(key).is_file()


@lru_cache
def get_storage() -> StorageService:
    settings = get_settings()
    if settings.STORAGE_BACKEND == "local":
        return LocalStorageService(settings.STORAGE_PATH)
    raise ValueError(f"Unsupported storage backend: {settings.STORAGE_BACKEND}")
