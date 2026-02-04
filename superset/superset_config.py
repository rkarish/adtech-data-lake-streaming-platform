SQLALCHEMY_DATABASE_URI = "postgresql+psycopg2://superset:superset@superset-postgres:5432/superset"

SECRET_KEY = "dev-secret-key-change-in-production"

CACHE_CONFIG = {
    "CACHE_TYPE": "SimpleCache",
    "CACHE_DEFAULT_TIMEOUT": 300
}

DATA_CACHE_CONFIG = {
    "CACHE_TYPE": "SimpleCache",
    "CACHE_DEFAULT_TIMEOUT": 300
}

FILTER_STATE_CACHE_CONFIG = {
    "CACHE_TYPE": "SimpleCache",
    "CACHE_DEFAULT_TIMEOUT": 300
}

EXPLORE_FORM_DATA_CACHE_CONFIG = {
    "CACHE_TYPE": "SimpleCache",
    "CACHE_DEFAULT_TIMEOUT": 300
}

WTF_CSRF_ENABLED = False


class CeleryConfig:
    broker_url = None


CELERY_CONFIG = CeleryConfig

SUPERSET_WEBSERVER_PORT = 8088
