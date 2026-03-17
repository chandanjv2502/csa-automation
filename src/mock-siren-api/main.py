"""
Mock Siren API
Mock API simulating Siren system for testing
"""
from fastapi import FastAPI
from datetime import datetime
import os

app = FastAPI(
    title="Mock Siren API",
    description="Mock API for Siren system integration testing",
    version="1.0.0"
)

@app.get("/")
async def root():
    return {
        "service": "mock-siren-api",
        "status": "running",
        "description": "Mock Siren API for testing"
    }

@app.get("/health")
async def health():
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "service": "mock-siren-api"
    }

@app.get("/info")
async def info():
    return {
        "service": "mock-siren-api",
        "version": "1.0.0",
        "purpose": "Simulate Siren API endpoints for testing",
        "environment": os.getenv("ENVIRONMENT", "development"),
        "uptime": "active"
    }

@app.get("/api/data")
async def get_data():
    return {
        "data": [
            {"id": 1, "type": "financial", "source": "SEC"},
            {"id": 2, "type": "rating", "source": "Moody's"}
        ]
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
