"""
main.py — FastAPI server for the Itri coach.
Run with: uvicorn main:app --reload --port 8000
"""

import asyncio
import hmac
import json
import logging
import os
import time
from collections import defaultdict, deque
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, Header, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from langchain_core.messages import AIMessage, HumanMessage
from pydantic import BaseModel

log = logging.getLogger("itri")

MAX_FACTS_CHARS = 12_000  # ~3k tokens; the app sends far less
MAX_MESSAGE_CHARS = 2_000
MAX_HISTORY_CHARS = 4_000  # per past message

# Shared secret the app sends in X-Itri-Key. Unset = open (local development only).
APP_KEY = os.environ.get("ITRI_APP_KEY", "")

# Per-client and whole-server limits, so a leaked URL can't drain the Gemini quota.
PER_CLIENT = (20, 600)  # 20 questions per 10 minutes
GLOBAL = (300, 3600)  # 300 questions per hour across everyone
_hits: dict[str, deque] = defaultdict(deque)


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


# No public API docs: they would advertise the endpoints.
app = FastAPI(title="Itri Coach", lifespan=lifespan, docs_url=None, redoc_url=None, openapi_url=None)

# The iOS/Android app doesn't need CORS. Only listed web origins (e.g. a future
# Flutter web build) may call from a browser: ALLOWED_ORIGINS="https://a,https://b".
_origins = [o.strip() for o in os.environ.get("ALLOWED_ORIGINS", "").split(",") if o.strip()]
if _origins:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=_origins,
        allow_methods=["POST"],
        allow_headers=["Content-Type", "X-Itri-Key"],
    )


def _client_ip(request: Request) -> str:
    fwd = request.headers.get("x-forwarded-for", "")
    return fwd.split(",")[0].strip() if fwd else (request.client.host if request.client else "unknown")


def _allow(bucket: str, limit: int, window: int) -> bool:
    now = time.monotonic()
    q = _hits[bucket]
    while q and now - q[0] > window:
        q.popleft()
    if len(q) >= limit:
        return False
    q.append(now)
    return True


def guard(request: Request, x_itri_key: str | None = Header(default=None)) -> None:
    """App key first, then rate limits. Runs before any Gemini call."""
    if APP_KEY and not hmac.compare_digest(x_itri_key or "", APP_KEY):
        raise HTTPException(status_code=401, detail="Unauthorised")
    if not _allow(f"ip:{_client_ip(request)}", *PER_CLIENT) or not _allow("global", *GLOBAL):
        raise HTTPException(status_code=429, detail="Too many requests. Try again in a few minutes.")


class ChatRequest(BaseModel):
    message: str
    history: list[list[str]] = []  # [[human_msg, ai_msg], ...]
    facts: str | None = None  # the user's exact figures, built by the app


def _inputs(body: ChatRequest) -> dict:
    if not body.message.strip():
        raise HTTPException(status_code=400, detail="Message cannot be empty")
    if len(body.message) > MAX_MESSAGE_CHARS:
        raise HTTPException(status_code=413, detail="Message too long")
    chat_history = []
    for pair in body.history[-10:]:
        if len(pair) == 2:
            chat_history.append(HumanMessage(content=pair[0][:MAX_HISTORY_CHARS]))
            chat_history.append(AIMessage(content=pair[1][:MAX_HISTORY_CHARS]))
    return {
        "question": body.message,
        "chat_history": chat_history,
        "facts": (body.facts or "")[:MAX_FACTS_CHARS],
    }


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/chat", dependencies=[Depends(guard)])
async def chat(request: Request, body: ChatRequest):
    inputs = _inputs(body)
    try:
        answer = await request.app.state.chain.ainvoke(inputs)
        return {"reply": answer}
    except Exception:
        log.exception("chat failed")  # details stay in the server log
        raise HTTPException(status_code=500, detail="The coach hit a problem answering that.")


@app.post("/chat-stream", dependencies=[Depends(guard)])
async def chat_stream(request: Request, body: ChatRequest):
    """
    Streaming version of /chat.
    Returns an SSE stream: each event is {"token": "..."}, ending with [DONE].
    """
    inputs = _inputs(body)

    async def generate():
        # Gemini sometimes answers 503 "high demand" (or 429) for a moment.
        # Retry quietly, but only before anything has been streamed.
        sent = False
        for attempt in range(3):
            try:
                async for chunk in request.app.state.chain.astream(inputs):
                    if chunk:
                        sent = True
                        yield f"data: {json.dumps({'token': chunk})}\n\n"
                break
            except Exception as e:
                busy = any(s in str(e) for s in ("503", "UNAVAILABLE", "429", "RESOURCE_EXHAUSTED"))
                if busy and not sent and attempt < 2:
                    log.warning("Gemini busy, retrying (attempt %d)", attempt + 1)
                    await asyncio.sleep(2 + 3 * attempt)
                    continue
                log.exception("chat-stream failed")  # details stay in the server log
                msg = ("Gemini is very busy right now. Try again in a minute."
                       if busy else "The coach hit a problem answering that.")
                yield f"data: {json.dumps({'error': msg})}\n\n"
                break
        yield "data: [DONE]\n\n"

    return StreamingResponse(
        generate(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )
