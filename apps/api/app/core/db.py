"""Accès Postgres : un pool asynchrone, des requêtes SQL écrites à la main."""
from contextlib import asynccontextmanager
from contextvars import ContextVar
from typing import Any, Sequence

from psycopg.rows import dict_row
from psycopg_pool import AsyncConnectionPool

from app.core.config import settings

_pool: AsyncConnectionPool | None = None

# Qui agit, pour le journal des modifications. Le trigger en base le lit dans
# `app.acteur` : il faut donc le poser dans la même transaction que l'écriture,
# et non une fois pour la connexion, qui sert ensuite à quelqu'un d'autre.
acteur: ContextVar[str | None] = ContextVar("acteur", default=None)


async def open_pool() -> None:
    global _pool
    if _pool is None:
        _pool = AsyncConnectionPool(
            settings.dsn, min_size=1, max_size=10, open=False, kwargs={"row_factory": dict_row}
        )
        await _pool.open(wait=True, timeout=10)


async def close_pool() -> None:
    global _pool
    if _pool is not None:
        await _pool.close()
        _pool = None


def pool() -> AsyncConnectionPool:
    if _pool is None:
        raise RuntimeError("Le pool n'est pas ouvert. open_pool() est appelé au démarrage.")
    return _pool


@asynccontextmanager
async def connection():
    async with pool().connection() as conn:
        await conn.execute("select set_config('app.acteur', %s, true)",
                           (acteur.get() or "systeme",))
        yield conn


async def fetch_all(sql: str, params: Sequence[Any] | dict | None = None) -> list[dict]:
    async with connection() as conn:
        cur = await conn.execute(sql, params)
        return await cur.fetchall()


async def fetch_one(sql: str, params: Sequence[Any] | dict | None = None) -> dict | None:
    async with connection() as conn:
        cur = await conn.execute(sql, params)
        return await cur.fetchone()


async def fetch_value(sql: str, params: Sequence[Any] | dict | None = None) -> Any:
    row = await fetch_one(sql, params)
    if row is None:
        return None
    return next(iter(row.values()))


async def execute(sql: str, params: Sequence[Any] | dict | None = None) -> int:
    async with connection() as conn:
        cur = await conn.execute(sql, params)
        return cur.rowcount
