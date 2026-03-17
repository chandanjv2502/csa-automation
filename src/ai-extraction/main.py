"""
AI Extraction Service
Performs OCR, IDP, and semantic search on documents
"""
from fastapi import FastAPI
from datetime import datetime
import os

app = FastAPI(
    title="AI Extraction Service",
    description="OCR/IDP, vector embeddings, and RAG-powered search",
    version="1.0.0"
)

@app.get("/")
async def root():
    return {
        "service": "ai-extraction",
        "status": "running",
        "description": "AI-powered document extraction and search"
    }

@app.get("/health")
async def health():
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "service": "ai-extraction"
    }

@app.get("/info")
async def info():
    return {
        "service": "ai-extraction",
        "version": "1.0.0",
        "purpose": "OCR, IDP, vector embeddings, semantic search, RAG Q&A",
        "environment": os.getenv("ENVIRONMENT", "development"),
        "uptime": "active"
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
