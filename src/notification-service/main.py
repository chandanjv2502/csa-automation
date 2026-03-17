"""
Notification Service
Sends notifications via email and other channels
"""
from fastapi import FastAPI
from datetime import datetime
import os

app = FastAPI(
    title="Notification Service",
    description="Multi-channel notification service",
    version="1.0.0"
)

@app.get("/")
async def root():
    return {
        "service": "notification-service",
        "status": "running",
        "description": "Multi-channel notification service"
    }

@app.get("/health")
async def health():
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "service": "notification-service"
    }

@app.get("/info")
async def info():
    return {
        "service": "notification-service",
        "version": "1.0.0",
        "purpose": "Send notifications via email, SMS, Slack",
        "environment": os.getenv("ENVIRONMENT", "development"),
        "uptime": "active"
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
