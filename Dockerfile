FROM python:3.9-slim

WORKDIR /app

COPY requirements.txt requirements.txt

RUN pip install --no-cache-dir -r requirements.txt

COPY docs docs
COPY mkdocs.yml mkdocs.yml

CMD ["mkdocs", "serve"]