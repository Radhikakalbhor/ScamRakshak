"""Authentication and Firebase Token Verification module for ScamRakshak backend.

Handles:
- Production Firebase ID token verification using firebase-admin SDK.
- Extraction of uid and verified phone number strictly from the token.
- Insecure local development mode (AUTH_DEV_MODE=1) with loud startup warning.
- FastAPI dependency for extracting and authenticating users via Bearer token.
"""

from __future__ import annotations

import logging
import os
from pathlib import Path
from typing import Optional

from fastapi import Depends, Header, HTTPException, status
from pydantic import BaseModel

logger = logging.getLogger("scamrakshak.auth")

# Check if development mode is enabled
AUTH_DEV_MODE: bool = os.environ.get("AUTH_DEV_MODE", "0").strip().lower() in ("1", "true", "yes")

_FIREBASE_INITIALIZED = False


def print_auth_mode_banner() -> None:
    """Prints a loud warning banner if AUTH_DEV_MODE is enabled."""
    if AUTH_DEV_MODE:
        banner = """
********************************************************************************
[SECURITY WARNING] AUTH_DEV_MODE IS CURRENTLY ENABLED!
- Insecure mock tokens ('mock-token:<uid>:<phone>') are accepted.
- Firebase signature verification is BYPASSED for local testing.
- DO NOT USE OR DEPLOY IN PRODUCTION!
********************************************************************************
"""
        print(banner, flush=True)
        logger.warning("AUTH_DEV_MODE is enabled. Mock tokens will be accepted.")
    else:
        logger.info("AUTH_DEV_MODE is disabled. Production Firebase ID token verification is active.")


def initialize_firebase() -> None:
    """Initializes firebase-admin SDK if not already initialized."""
    global _FIREBASE_INITIALIZED
    if _FIREBASE_INITIALIZED or AUTH_DEV_MODE:
        return

    try:
        import firebase_admin
        from firebase_admin import credentials

        if not firebase_admin._apps:
            # Check for service account key path in env or default local file
            key_path_env = os.environ.get("FIREBASE_SERVICE_ACCOUNT_PATH")
            default_key_path = Path(__file__).resolve().parent / "service-account.json"

            if key_path_env and Path(key_path_env).is_file():
                cred = credentials.Certificate(key_path_env)
                firebase_admin.initialize_app(cred)
                logger.info("Firebase Admin SDK initialized using key at: %s", key_path_env)
            elif default_key_path.is_file():
                cred = credentials.Certificate(str(default_key_path))
                firebase_admin.initialize_app(cred)
                logger.info("Firebase Admin SDK initialized using: %s", default_key_path)
            else:
                # Fallback to default application credentials (e.g. GOOGLE_APPLICATION_CREDENTIALS)
                firebase_admin.initialize_app()
                logger.info("Firebase Admin SDK initialized with application default credentials.")

        _FIREBASE_INITIALIZED = True
    except Exception as exc:
        logger.warning(
            "Firebase Admin SDK initialization deferred or failed: %s. "
            "(Ensure service-account.json is present or set AUTH_DEV_MODE=1 for local tests)",
            exc,
        )


class AuthUser(BaseModel):
    """Authenticated user identity extracted strictly from verified token."""
    uid: str
    phone: str


def verify_firebase_token(token: str) -> AuthUser:
    """Verifies Firebase ID token and extracts uid and verified phone number.

    In production: Uses firebase_admin.auth.verify_id_token.
    In AUTH_DEV_MODE: Accepts 'mock-token:<uid>:<phone>' or 'mock-token-<uid>-<phone>'.
    """
    token = token.strip()
    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token is empty.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    # 1. Dev Mode Mock Token Handling
    if AUTH_DEV_MODE:
        if token.startswith("mock-token:") or token.startswith("test-token:") or token.startswith("dev-token:"):
            parts = token.split(":")
            if len(parts) >= 3:
                return AuthUser(uid=parts[1].strip(), phone=parts[2].strip())
            elif len(parts) == 2:
                return AuthUser(uid=parts[1].strip(), phone="+919999999999")
        elif token.startswith("mock-token-") or token.startswith("test-token-") or token.startswith("dev-token-"):
            parts = token.split("-", 2)
            if len(parts) >= 3:
                # Format: mock-token-<uid>-<phone>
                subparts = parts[2].split("-", 1)
                uid = subparts[0].strip()
                phone = subparts[1].strip() if len(subparts) > 1 else "+919999999999"
                return AuthUser(uid=uid, phone=phone)

        # If in dev mode but invalid mock format and firebase is not initialized
        if not _FIREBASE_INITIALIZED:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="In AUTH_DEV_MODE, use format 'mock-token:<uid>:<phone>'.",
                headers={"WWW-Authenticate": "Bearer"},
            )

    # 2. Production Firebase Token Verification
    initialize_firebase()
    try:
        import firebase_admin.auth

        decoded = firebase_admin.auth.verify_id_token(token)
        uid = decoded.get("uid")
        # In Firebase phone authentication, the verified phone is in 'phone_number'
        phone = decoded.get("phone_number") or ""

        if not uid:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Token does not contain a valid user ID.",
                headers={"WWW-Authenticate": "Bearer"},
            )
        if not phone:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Token does not contain a verified phone number.",
                headers={"WWW-Authenticate": "Bearer"},
            )

        return AuthUser(uid=uid, phone=phone)

    except HTTPException:
        raise
    except Exception as exc:
        logger.error("Token verification failed: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid or expired authentication token: {exc}",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc


def get_current_user(authorization: Optional[str] = Header(None)) -> AuthUser:
    """FastAPI dependency requiring a valid Bearer token."""
    if not authorization:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing Authorization header.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    parts = authorization.split()
    if len(parts) != 2 or parts[0].lower() != "bearer":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authorization header must follow 'Bearer <token>' format.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    return verify_firebase_token(parts[1])


def get_optional_user(authorization: Optional[str] = Header(None)) -> Optional[AuthUser]:
    """FastAPI dependency for optional authentication (e.g. anonymous report submission)."""
    if not authorization:
        return None

    parts = authorization.split()
    if len(parts) != 2 or parts[0].lower() != "bearer":
        return None

    try:
        return verify_firebase_token(parts[1])
    except HTTPException:
        return None
