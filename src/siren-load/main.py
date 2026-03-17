"""
Siren Load Service
Loads data into Siren system
"""
from fastapi import FastAPI
from datetime import datetime
import os

app = FastAPI(
    title="Siren Load Service",
    description="Data loading service for Siren integration",
    version="1.0.0"
)

@app.get("/")
async def root():
    return {
        "service": "siren-load",
        "status": "running",
        "description": "Siren data loading service"
    }

@app.get("/health")
async def health():
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "service": "siren-load"
    }

@app.get("/info")
async def info():
    return {
        "service": "siren-load",
        "version": "1.0.0",
        "purpose": "Load processed data into Siren system",
        "environment": os.getenv("ENVIRONMENT", "development"),
        "uptime": "active"
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
