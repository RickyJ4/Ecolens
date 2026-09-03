import firebase_admin
from firebase_admin import credentials, firestore

class FirebaseClient:
    _app = None
    _db = None

    @classmethod
    def initialize(cls, service_account_path: str):
        if not cls._app:
            cred = credentials.Certificate(service_account_path)
            cls._app = firebase_admin.initialize_app(cred)
            cls._db = firestore.client()
        return cls._db

    @classmethod
    def db(cls):
        if not cls._db:
            raise RuntimeError("Firebase not initialized. Call initialize() first.")
        return cls._db
