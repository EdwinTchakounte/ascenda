"""Configuration de l'API, lue depuis le .env à la racine du dépôt."""
from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

def _racine() -> Path:
    """La racine du dépôt, ou le répertoire de travail dans une image."""
    depart = Path(__file__).resolve()
    for candidat in depart.parents:
        if (candidat / ".env").is_file() or (candidat / ".git").exists():
            return candidat
    return Path.cwd()


ROOT = _racine()


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=ROOT / ".env", env_file_encoding="utf-8", extra="ignore"
    )

    # ---- base de données
    postgres_host: str = "localhost"
    postgres_port: int = 5450
    postgres_db: str = "ascenda"
    postgres_user: str = "ascenda"
    postgres_password: str = ""

    # ---- service
    api_port: int = 8250
    api_env: str = "dev"
    api_cors_origins: str = "http://localhost:3251,http://localhost:3250,http://localhost:8250"

    jwt_secret: str = "dev-secret-a-remplacer"
    jwt_algorithm: str = "HS256"
    access_token_minutes: int = 30
    refresh_token_days: int = 60

    # ---- agent
    anthropic_api_key: str = ""
    agent_model: str = "claude-opus-5"
    agent_max_context_chunks: int = 8
    # Le modèle qui vectorise le corpus.
    embed_model: str = "intfloat/multilingual-e5-large"

    dossier_livres: str = str(ROOT / "livres")
    taille_max_import: int = 100 * 1024 * 1024

    tara_api_key: str = ""
    tara_business_id: str = ""
    public_base_url: str = "http://localhost:8250"
    # Ces deux réglages valident des paiements sans passer par Tara.
    paiement_test_auto_valide: bool = False
    reconciliation_timeout_heures: int = 24
    reconciliation_pause_secondes: float = 20.0

    # ---- courrier
    brevo_api_key: str = ""
    mail_expediteur: str = "ASCENDA <ne-pas-repondre@ascenda-books.online>"

    # ---- stockage
    minio_endpoint: str = "localhost:9250"
    minio_root_user: str = "ascenda"
    minio_root_password: str = ""
    minio_bucket: str = "ascenda-docs"
    minio_secure: bool = False

    @property
    def dsn(self) -> str:
        return (
            f"host={self.postgres_host} port={self.postgres_port} "
            f"dbname={self.postgres_db} user={self.postgres_user} "
            f"password={self.postgres_password}"
        )

    @property
    def cors_origins(self) -> list[str]:
        return [o.strip() for o in self.api_cors_origins.split(",") if o.strip()]

    @property
    def is_prod(self) -> bool:
        return self.api_env.lower() in ("prod", "production")


@lru_cache
def get_settings() -> Settings:
    s = Settings()
    if s.is_prod and s.jwt_secret == "dev-secret-a-remplacer":
        raise RuntimeError(
            "JWT_SECRET n'est pas défini alors que API_ENV=prod. "
            "Poser une valeur aléatoire longue dans le .env avant de démarrer."
        )
    if s.is_prod and s.paiement_test_auto_valide:
        raise RuntimeError(
            "PAIEMENT_TEST_AUTO_VALIDE est actif alors que API_ENV=prod. "
            "Ce réglage valide les paiements sans encaissement réel."
        )
    return s


settings = get_settings()
