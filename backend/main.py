"""
main.py — FastAPI server for the Itri coach.
Run with: uvicorn main:app --reload --port 8000
"""

import asyncio
import json
import os
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from langchain_core.messages import AIMessage, HumanMessage
from pydantic import BaseModel

MAX_FACTS_CHARS = 12_000  # ~3k tokens; the app sends far less


def _collection_seeded(client, name: str, expected: int) -> bool:
    """True if the Qdrant collection holds exactly the current set of papers."""
    try:
        return client.get_collection(name).points_count == expected
    except Exception:
        return False


def _seed_research_if_needed() -> None:
    """Re-seed the research papers when the stored set differs from the list.
    Runs in the background: a slow or unreachable Qdrant must never stop the
    server from starting (the coach then answers without the papers)."""
    try:
        from qdrant_client import QdrantClient
        from ingest_research import RESEARCH_PAPERS, ingest_research

        client = QdrantClient(url=os.environ["QDRANT_URL"], api_key=os.environ["QDRANT_API_KEY"], timeout=20)
        try:
            if not _collection_seeded(client, "research_papers", len(RESEARCH_PAPERS)):
                print(f"Qdrant 'research_papers' out of date: re-seeding {len(RESEARCH_PAPERS)} papers...")
                ingest_research()
        finally:
            client.close()
    except Exception as e:
        print(f"Research seeding skipped: {e}")


@asynccontextmanager
async def lifespan(app: FastAPI):
    from rag_chain import chain as _chain

    app.state.chain = _chain
    seeding = asyncio.create_task(asyncio.to_thread(_seed_research_if_needed))
    print("Coach chain ready.")
    yield
    seeding.cancel()


app = FastAPI(title="Itri Coach", lifespan=lifespan)

# CORS — required for Flutter web
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # tighten this in production
    allow_methods=["POST", "GET"],
    allow_headers=["*"],
)


class ChatRequest(BaseModel):
    message: str
    history: list[list[str]] = []  # [[human_msg, ai_msg], ...]
    facts: str | None = None  # the user's exact figures, built by the app


def _inputs(body: ChatRequest) -> dict:
    if not body.message.strip():
        raise HTTPException(status_code=400, detail="Message cannot be empty")
    chat_history = []
    for pair in body.history[-10:]:
        if len(pair) == 2:
            chat_history.append(HumanMessage(content=pair[0]))
            chat_history.append(AIMessage(content=pair[1]))
    return {
        "question": body.message,
        "chat_history": chat_history,
        "facts": (body.facts or "")[:MAX_FACTS_CHARS],
    }


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/chat")
async def chat(request: Request, body: ChatRequest):
    inputs = _inputs(body)
    try:
        answer = await request.app.state.chain.ainvoke(inputs)
        return {"reply": answer}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/chat-stream")
async def chat_stream(request: Request, body: ChatRequest):
    """
    Streaming version of /chat.
    Returns an SSE stream: each event is {"token": "..."}, ending with [DONE].
    """
    inputs = _inputs(body)

    async def generate():
        try:
            async for chunk in request.app.state.chain.astream(inputs):
                if chunk:
                    yield f"data: {json.dumps({'token': chunk})}\n\n"
        except Exception as e:
            yield f"data: {json.dumps({'error': str(e)})}\n\n"
        finally:
            yield "data: [DONE]\n\n"

    return StreamingResponse(
        generate(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )
