"""
Ingestion Service - Processes documents and creates vector embeddings
"""
import os
import logging
import json
import hashlib
from datetime import datetime
from fastapi import FastAPI, HTTPException
import boto3
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
SQS_QUEUE_URL = os.getenv("SQS_QUEUE_URL", "")
CHUNK_SIZE = int(os.getenv("CHUNK_SIZE", "512"))

# AWS clients
dynamodb = boto3.resource('dynamodb', region_name=AWS_REGION)
s3 = boto3.client('s3', region_name=AWS_REGION)
sqs = boto3.client('sqs', region_name=AWS_REGION)

# Metrics
ingestion_counter = Counter('ingestion_total', 'Total documents ingested')
ingestion_duration = Histogram('ingestion_duration_seconds', 'Ingestion duration')
chunk_counter = Counter('chunks_created_total', 'Total chunks created')

app = FastAPI(title="Ingestion Service", version="1.0.0")


def chunk_text(text: str, chunk_size: int = CHUNK_SIZE) -> list[str]:
    """Split text into chunks"""
    words = text.split()
    chunks = []
    current_chunk = []
    current_size = 0
    
    for word in words:
        current_chunk.append(word)
        current_size += len(word) + 1
        
        if current_size >= chunk_size:
            chunks.append(' '.join(current_chunk))
            current_chunk = []
            current_size = 0
    
    if current_chunk:
        chunks.append(' '.join(current_chunk))
    
    return chunks


def create_mock_embedding(text: str) -> list[float]:
    """Create a mock embedding vector"""
    # In production, call an embedding service
    # For now, create a deterministic mock based on text hash
    hash_obj = hashlib.md5(text.encode())
    hash_int = int(hash_obj.hexdigest(), 16)
    
    # Create 768-dimensional vector
    vector = []
    for i in range(768):
        val = ((hash_int >> (i % 32)) & 0xFF) / 255.0
        vector.append(val)
    
    return vector


@app.get("/health")
async def health():
    """Health check endpoint"""
    return {"status": "healthy"}


@app.get("/ready")
async def ready():
    """Readiness check endpoint"""
    try:
        # Check SQS connectivity
        sqs.get_queue_attributes(
            QueueUrl=SQS_QUEUE_URL,
            AttributeNames=['QueueArn']
        )
        return {"status": "ready"}
    except Exception as e:
        logger.error(f"Readiness check failed: {e}")
        raise HTTPException(status_code=503, detail="Service not ready")


@app.get("/metrics")
async def metrics():
    """Prometheus metrics endpoint"""
    return Response(content=generate_latest(), media_type="text/plain")


@app.post("/api/v1/ingest")
@ingestion_duration.time()
async def ingest_document(document_id: str, content: str):
    """
    Ingest a document
    
    1. Store original document in S3
    2. Chunk the document
    3. Create embeddings for each chunk
    4. Store vectors in S3 and metadata in DynamoDB
    """
    ingestion_counter.inc()
    
    logger.info(f"Ingesting document: {document_id}")
    
    try:
        # Store original document
        s3.put_object(
            Bucket=S3_DOCUMENTS_BUCKET,
            Key=f"{document_id}/original.txt",
            Body=content.encode('utf-8')
        )
        
        # Chunk document
        chunks = chunk_text(content)
        chunk_counter.inc(len(chunks))
        
        logger.info(f"Created {len(chunks)} chunks for {document_id}")
        
        # Process each chunk
        table = dynamodb.Table(DYNAMODB_TABLE)
        
        for i, chunk in enumerate(chunks):
            chunk_id = f"chunk_{i:04d}"
            
            # Store chunk
            s3.put_object(
                Bucket=S3_DOCUMENTS_BUCKET,
                Key=f"{document_id}/{chunk_id}.txt",
                Body=chunk.encode('utf-8')
            )
            
            # Create embedding
            embedding = create_mock_embedding(chunk)
            
            # Store vector
            s3.put_object(
                Bucket=S3_VECTORS_BUCKET,
                Key=f"{document_id}/{chunk_id}.json",
                Body=json.dumps({"vector": embedding}).encode('utf-8')
            )
            
            # Store metadata in DynamoDB
            table.put_item(
                Item={
                    'document_id': document_id,
                    'chunk_id': chunk_id,
                    'chunk_index': i,
                    'chunk_text_preview': chunk[:100],
                    'vector_s3_key': f"{document_id}/{chunk_id}.json",
                    'created_at': int(datetime.utcnow().timestamp())
                }
            )
        
        return {
            "status": "success",
            "document_id": document_id,
            "chunks_created": len(chunks)
        }
        
    except Exception as e:
        logger.error(f"Ingestion failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


async def process_sqs_messages():
    """Background task to process SQS messages"""
    while True:
        try:
            response = sqs.receive_message(
                QueueUrl=SQS_QUEUE_URL,
                MaxNumberOfMessages=1,
                WaitTimeSeconds=20
            )
            
            messages = response.get('Messages', [])
            
            for message in messages:
                body = json.loads(message['Body'])
                document_id = body.get('document_id')
                content = body.get('content')
                
                await ingest_document(document_id, content)
                
                # Delete message from queue
                sqs.delete_message(
                    QueueUrl=SQS_QUEUE_URL,
                    ReceiptHandle=message['ReceiptHandle']
                )
                
        except Exception as e:
            logger.error(f"SQS processing error: {e}")
            await asyncio.sleep(5)


if __name__ == "__main__":
    import uvicorn
    import asyncio
    
    # Start SQS processor in background
    # asyncio.create_task(process_sqs_messages())
    
    uvicorn.run(app, host="0.0.0.0", port=8081)
