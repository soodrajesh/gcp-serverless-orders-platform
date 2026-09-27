import os
from datetime import datetime, timezone

_db = None


def db():
    global _db
    if _db is None:
        from google.cloud import firestore

        _db = firestore.Client(project=os.environ["GCP_PROJECT"], database=os.environ["FIRESTORE_DB"])
    return _db


def now():
    return datetime.now(timezone.utc)
