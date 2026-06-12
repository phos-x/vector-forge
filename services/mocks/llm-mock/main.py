"""
Mock LLM Service - OpenAI-compatible API for testing
"""
import os
import time
import random
from fastapi import FastAPI
from pydantic import BaseModel

RESPONSE_DELAY_MS = int(os.getenv("RESPONSE_DELAY_MS", "100"))

app = FastAPI(title="LLM Mock", version="1.0.0")


class Message(BaseModel):
    role: str
    content: str


class ChatRequest(BaseModel):
    messages: list[Message]
    max_tokens: int = 500
    temperature: float = 0.7


class ChatResponse(BaseModel):
    id: str
    object: str = "chat.completion"
    created: int
    model: str = "mock-gpt-3.5-turbo"
    choices: list[dict]


@app.post("/v1/chat/completions")
async def chat_completions(request: ChatRequest) -> ChatResponse:
    """
    Mock OpenAI-compatible chat completions endpoint
    Returns a deterministic mock response with simulated latency
    """
    # Simulate processing time
    time.sleep(RESPONSE_DELAY_MS / 1000.0)
    
    # Get the last user message
    user_messages = [msg for msg in request.messages if msg.role == "user"]
    last_message = user_messages[-1].content if user_messages else ""
    
    # Generate mock response
    mock_responses = [
        "Based on the provided context, here's what I found: This is a mock response from the LLM service. In a production environment, this would be replaced with an actual language model API.",
        "According to the information provided, the system demonstrates a well-architected RAG pipeline with clear separation between query and ingestion paths.",
        "The context suggests this is a platform engineering demo focusing on infrastructure-as-code and Kubernetes best practices.",
    ]
    
    response_text = random.choice(mock_responses)
    
    # Add some context-awareness
    if "vector" in last_message.lower():
        response_text = "Vector embeddings are used to represent documents in a high-dimensional space, enabling semantic similarity search."
    elif "kubernetes" in last_message.lower():
        response_text = "Kubernetes provides container orchestration with features like auto-scaling, self-healing, and declarative configuration management."
    
    return ChatResponse(
        id=f"chatcmpl-{int(time.time())}",
        created=int(time.time()),
        choices=[
            {
                "index": 0,
                "message": {
                    "role": "assistant",
                    "content": response_text
                },
                "finish_reason": "stop"
            }
        ]
    )


@app.get("/health")
async def health():
    return {"status": "healthy", "service": "llm-mock"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
