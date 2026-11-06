from datetime import timedelta
from flask import session, Flask

# Время жизни сессии (24 часа)
PERMANENT_SESSION_LIFETIME = timedelta(hours=24)

def make_session_permanent():
    session.permanent = True

# Хук, который применяет настройку при каждом запросе
def FLASK_APP_MUTATOR(app: Flask) -> None:
    app.before_request_funcs.setdefault(None, []).append(make_session_permanent)