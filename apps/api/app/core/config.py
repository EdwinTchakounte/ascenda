"""Configuration de l'API, lue depuis le .env à la racine du dépôt."""
from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

def _racine() -> Path:
    """La racine du dépôt, ou le répertoire de travail dans une image.

    En développement le fichier vit dans apps/api/app/core/, à quatre niveaux
    de la racine. Dans l'image Docker le code est copié à plat sous /app et ces
    quatre niveaux n'existent pas : la remontée levait IndexError et le
    conteneur mourait avant d'ouvrir le premier port. On remonte donc tant
    qu'il y a un parent, et on s'arrête au premier répertoire qui porte un
    .env ou un .git.
    """
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

    # ---- jetons
    # En production, JWT_SECRET doit être posé dans le .env : la valeur par défaut
    # ne sert qu'au développement local et l'API refuse de démarrer sans elle en prod.
    jwt_secret: str = "dev-secret-a-remplacer"
    jwt_algorithm: str = "HS256"
    access_token_minutes: int = 30
    refresh_token_days: int = 60

    # ---- agent
    anthropic_api_key: str = ""
    agent_model: str = "claude-opus-5"
    agent_max_context_chunks: int = 8
    # Le modèle qui vectorise le corpus. Doit correspondre à la dimension
    # de la colonne `chunk.embedding`.
    embed_model: str = "intfloat/multilingual-e5-large"

    # ---- paiement
    # Sans identifiants, le fournisseur passe en mode simulé : utile en
    # développement, refusé en production par la vérification ci-dessous.
    tara_api_key: str = ""
    tara_business_id: str = ""
    public_base_url: str = "http://localhost:8250"
    # Ces deux réglages valident des paiements sans passer par Tara.
    # Ils ne doivent jamais valoir true en production.
    paiement_test_auto_valide: bool = False
    reconciliation_timeout_heures: int = 24
    reconciliation_pause_secondes: float = 20.0

    # ---- courrier
    brevo_api_key: str = ""
    mail_expediteur: str = "ASCENDA <ne-pas-repondre@ascenda.app>"

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
