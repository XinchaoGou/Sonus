"""Load engine registry from bundled YAML manifest."""

from __future__ import annotations

from dataclasses import dataclass, field
from functools import lru_cache
from importlib import resources
from pathlib import Path
from typing import Any

import yaml


@dataclass(frozen=True)
class EngineAsset:
    filename: str
    url: str


@dataclass(frozen=True)
class EngineSpec:
    id: str
    name: str
    optional_dependency: str | None = None
    openai_model_aliases: tuple[str, ...] = ()
    assets: tuple[EngineAsset, ...] = ()
    huggingface_repo: str | None = None
    model_subdir: str | None = None
    readiness_files: tuple[str, ...] = ()


@dataclass(frozen=True)
class EngineManifest:
    engines: dict[str, EngineSpec]

    def get(self, engine_id: str) -> EngineSpec | None:
        return self.engines.get(engine_id)

    def list_ids(self) -> list[str]:
        return sorted(self.engines.keys())


def _parse_engine(engine_id: str, raw: dict[str, Any]) -> EngineSpec:
    assets = tuple(
        EngineAsset(filename=item["filename"], url=item["url"])
        for item in raw.get("assets", [])
    )
    aliases = tuple(str(alias) for alias in raw.get("openai_model_aliases", []))
    readiness = tuple(str(name) for name in raw.get("readiness_files", []))
    return EngineSpec(
        id=engine_id,
        name=str(raw.get("name", engine_id)),
        optional_dependency=raw.get("optional_dependency"),
        openai_model_aliases=aliases,
        assets=assets,
        huggingface_repo=raw.get("huggingface_repo"),
        model_subdir=raw.get("model_subdir"),
        readiness_files=readiness,
    )


@lru_cache(maxsize=1)
def load_engine_manifest() -> EngineManifest:
    with resources.files("sonus").joinpath("engine_manifest.yaml").open("r", encoding="utf-8") as fh:
        data = yaml.safe_load(fh)
    engines = {
        engine_id: _parse_engine(engine_id, raw)
        for engine_id, raw in (data.get("engines") or {}).items()
    }
    return EngineManifest(engines=engines)


def manifest_path() -> Path:
    return Path(resources.files("sonus")) / "engine_manifest.yaml"
