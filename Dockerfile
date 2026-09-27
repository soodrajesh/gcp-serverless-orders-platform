FROM python:3.13-slim
ENV PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1
WORKDIR /srv
COPY app/requirements.txt app/requirements.txt
RUN pip install -r app/requirements.txt
COPY app app
RUN useradd -r -u 10001 app
USER 10001
# each Cloud Run service overrides the target (app.orders / app.inventory / app.payments)
CMD ["gunicorn", "--bind=:8080", "--workers=1", "--threads=8", "app.orders:app"]
