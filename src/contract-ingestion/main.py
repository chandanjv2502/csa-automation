"""
Contract Ingestion Service
Retrieves and organizes documents from various sources
"""
from fastapi import FastAPI
from datetime import datetime
import os

app = FastAPI(
    title="Contract Ingestion Service",
    description="Retrieves and organizes documents from SEC EDGAR and other sources",
    version="1.0.0"
)

@app.get("/")
async def root():
    return {
        "service": "contract-ingestion",
        "status": "running",
        "description": "Document retrieval and organization service"
    }

@app.get("/health")
async def health():
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "service": "contract-ingestion"
    }

@app.get("/info")
async def info():
    return {
        "service": "contract-ingestion",
        "version": "1.0.0",
        "purpose": "Document retrieval from SEC EDGAR, IR websites, internal repos",
        "environment": os.getenv("ENVIRONMENT", "development"),
        "uptime": "active"
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
