"""
Contract Discovery Service
Monitors email inbox and creates workflow cases
"""
from fastapi import FastAPI
from datetime import datetime
import os

app = FastAPI(
    title="Contract Discovery Service",
    description="Monitors email inbox for trade intentions and creates workflow cases",
    version="1.0.0"
)

@app.get("/")
async def root():
    return {
        "service": "contract-discovery",
        "status": "running",
        "description": "Monitors email inbox and creates workflow cases"
    }

@app.get("/health")
async def health():
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "service": "contract-discovery"
    }

@app.get("/info")
async def info():
    return {
        "service": "contract-discovery",
        "version": "1.0.0",
        "purpose": "Email monitoring and case creation",
        "environment": os.getenv("ENVIRONMENT", "development"),
        "uptime": "active"
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
