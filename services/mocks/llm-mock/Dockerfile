FROM python:3.11-slim

WORKDIR /app

RUN pip install --no-cache-dir fastapi==0.104.1 uvicorn[standard]==0.24.0

COPY main.py .

EXPOSE 8080

CMD ["python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
