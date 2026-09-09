"""Erreurs métier. Le message est destiné à l'utilisateur : il est en français
et dit quoi faire, pas seulement ce qui a échoué."""
from fastapi import HTTPException, status


class ApiError(HTTPException):
    code: str = "erreur"

    def __init__(self, detail: str, status_code: int = 400, code: str | None = None):
        super().__init__(status_code=status_code, detail={"code": code or self.code, "message": detail})


class NotFound(ApiError):
    def __init__(self, quoi: str = "Ressource introuvable."):
        super().__init__(quoi, status.HTTP_404_NOT_FOUND, "introuvable")


class Unauthorized(ApiError):
    def __init__(self, detail: str = "Session expirée ou absente. Reconnectez-vous."):
        super().__init__(detail, status.HTTP_401_UNAUTHORIZED, "non_authentifie")


class Forbidden(ApiError):
    def __init__(self, detail: str = "Cette ressource ne vous appartient pas."):
        super().__init__(detail, status.HTTP_403_FORBIDDEN, "interdit")


class Conflict(ApiError):
    def __init__(self, detail: str):
        super().__init__(detail, status.HTTP_409_CONFLICT, "conflit")


class QuotaExceeded(ApiError):
    def __init__(self, detail: str, quota: dict | None = None):
        super().__init__(detail, status.HTTP_402_PAYMENT_REQUIRED, "quota_depasse")
        if quota:
            self.detail["quota"] = quota
