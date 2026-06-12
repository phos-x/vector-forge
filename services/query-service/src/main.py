"""
Query Service - Handles RAG queries and retrieval
"""
import os
import logging
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import boto3
import httpx
from prometheus_client import Counter, Histogram, generate_latest
from fastapi.responses import Response

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Environment variables
AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
DYNAMODB_TABLE = os.getenv("DYNAMODB_TABLE", "")
S3_DOCUMENTS_BUCKET = os.getenv("S3_DOCUMENTS_BUCKET", "")
S3_VECTORS_BUCKET = os.getenv("S3_VECTORS_BUCKET", "")
LLM_ENDPOINT = os.getenv("LLM_ENDPOINT", "http://llm-mock:8080")
MAX_RESULTS = int(os.getenv("MAX_RESULTS", "5"))

# AWS clients
dynamodb = boto3.resource('dynamodb', region_name=AWS_REGION)
s3 = boto3.client('s3', region_name=AWS_REGION)

# Metrics
query_counter = Counter('query_total', 'Total number of queries')
query_duration = Histogram('query_duration_seconds', 'Query duration in seconds')
llm_call_duration = Histogram('llm_call_duration_seconds', 'LLM call duration in seconds')

app = FastAPI(title="Query Service", version="1.0.0")


class QueryRequest(BaseModel):
    query: str
    max_results: int = MAX_RESULTS


class QueryResponse(BaseModel):
    answer: str
    sources: list[str]
    took_ms: int


@app.get("/health")
async def health():
    """Health check endpoint"""
    return {"status": "healthy"}


@app.get("/ready")
async def ready():
    """Readiness check endpoint"""
    # Check DynamoDB connectivity
    try:
        table = dynamodb.Table(DYNAMODB_TABLE)
        table.table_status
        return {"status": "ready"}
    except Exception as e:
        logger.error(f"Readiness check failed: {e}")
        raise HTTPException(status_code=503, detail="Service not ready")


@app.get("/metrics")
async def metrics():
    """Prometheus metrics endpoint"""
    return Response(content=generate_latest(), media_type="text/plain")


@app.post("/api/v1/query", response_model=QueryResponse)
@query_duration.time()
async def query(request: QueryRequest):
    """
    Process a RAG query
    
    1. Convert query to vector (mock)
    2. Search DynamoDB for similar vectors
    3. Retrieve documents from S3
    4. Send to LLM with context
    5. Return response
    """
    query_counter.inc()
    
    logger.info(f"Processing query: {request.query}")
    
    try:
        # Step 1: Mock vector search
        # In production, this would call an embedding service
        query_vector = [0.1] * 768  # Mock embedding
        
        # Step 2: Search DynamoDB for similar vectors
        table = dynamodb.Table(DYNAMODB_TABLE)
        
        # Mock similarity search - in production use vector similarity
        response = table.scan(Limit=request.max_results)
        items = response.get('Items', [])
        
        # Step 3: Retrieve document chunks from S3
        contexts = []
        sources = []
        for item in items:
            doc_id = item.get('document_id')
            chunk_id = item.get('chunk_id')
            
            # Retrieve document chunk
            try:
                obj = s3.get_object(
                    Bucket=S3_DOCUMENTS_BUCKET,
                    Key=f"{doc_id}/{chunk_id}.txt"
                )
                content = obj['Body'].read().decode('utf-8')
                contexts.append(content)
                sources.append(f"{doc_id}#{chunk_id}")
            except Exception as e:
                logger.warning(f"Failed to retrieve {doc_id}/{chunk_id}: {e}")
        
        # Step 4: Call LLM with context
        llm_prompt = f"""Answer the question based on the following context:

Context:
{chr(10).join(contexts)}

Question: {request.query}

Answer:"""
        
        with llm_call_duration.time():
            async with httpx.AsyncClient() as client:
                llm_response = await client.post(
                    f"{LLM_ENDPOINT}/v1/chat/completions",
                    json={
                        "messages": [
                            {"role": "user", "content": llm_prompt}
                        ],
                        "max_tokens": 500
                    },
                    timeout=30.0
                )
        
        llm_response.raise_for_status()
        answer = llm_response.json().get("choices", [{}])[0].get("message", {}).get("content", "")
        
        return QueryResponse(
            answer=answer,
            sources=sources,
            took_ms=100  # Would calculate actual time
        )
        
    except Exception as e:
        logger.error(f"Query failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
