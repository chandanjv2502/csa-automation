"""
Mock Phoenix API
Mock API simulating Phoenix system for testing
"""
from fastapi import FastAPI
from datetime import datetime
import os

app = FastAPI(
    title="Mock Phoenix API",
    description="Mock API for Phoenix system integration testing",
    version="1.0.0"
)

@app.get("/")
async def root():
    return {
        "service": "mock-phoenix-api",
        "status": "running",
        "description": "Mock Phoenix API for testing"
    }

@app.get("/health")
async def health():
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "service": "mock-phoenix-api"
    }

@app.get("/info")
async def info():
    return {
        "service": "mock-phoenix-api",
        "version": "1.0.0",
        "purpose": "Simulate Phoenix API endpoints for testing",
        "environment": os.getenv("ENVIRONMENT", "development"),
        "uptime": "active"
    }

@app.get("/api/contracts")
async def get_contracts():
    return {
        "contracts": [
            {"id": "CSA-001", "counterparty": "Test Corp", "status": "active"},
            {"id": "CSA-002", "counterparty": "Demo Inc", "status": "pending"}
        ]
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
