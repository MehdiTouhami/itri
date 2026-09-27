"""
rag_chain.py — Itri coach: the user's exact numbers + research retrieval.

Personal data is no longer retrieved by vector similarity. The app computes
the user's figures (training, sleep, HRV, readiness) on the phone and sends
them as `facts` with every question, so answers use real dates and averages
instead of whichever nights happened to embed closest to the question.

Research papers are still retrieved from Qdrant: that is what RAG is good at.
"""

import os
from dotenv import load_dotenv
from langchain_google_genai import GoogleGenerativeAIEmbeddings, ChatGoogleGenerativeAI
from langchain_qdrant import QdrantVectorStore
from qdrant_client import QdrantClient
from langchain_core.prompts import ChatPromptTemplate, MessagesPlaceholder
from langchain_core.output_parsers import StrOutputParser
from langchain_core.runnables import RunnableLambda

load_dotenv()

QDRANT_URL = os.environ["QDRANT_URL"]
QDRANT_API_KEY = os.environ["QDRANT_API_KEY"]
RESEARCH_COLLECTION = "research_papers"

qdrant_client = QdrantClient(url=QDRANT_URL, api_key=QDRANT_API_KEY, timeout=10)
embeddings = GoogleGenerativeAIEmbeddings(model="models/gemini-embedding-001")

_research_retriever = None


def _retriever():
    """Built on first use, so a paused or unreachable Qdrant can't stop the
    server from starting."""
    global _research_retriever
    if _research_retriever is None:
        store = QdrantVectorStore(client=qdrant_client, collection_name=RESEARCH_COLLECTION, embedding=embeddings)
        _research_retriever = store.as_retriever(search_kwargs={"k": 3})
    return _research_retriever

llm = ChatGoogleGenerativeAI(model="gemini-3.6-flash", temperature=0.7)

SYSTEM_PROMPT = """You are Itri, the coach inside the Itri app, which covers both training and recovery (sleep, HRV, resting heart rate).

You have two sources:

1. THE USER'S DATA: exact figures computed by the app from their Garmin watch.
2. RESEARCH: peer-reviewed findings retrieved for this question.

Rules:
- Use only numbers that appear in the user's data. Do not calculate new statistics, percentages or averages of your own; compare the figures you are given instead.
- Refer to days by date or weekday as given. Do not invent dates.
- Back advice with the research where it applies, naming the topic or authors.
- Connect training and sleep when the data supports it; that is what makes this coach useful.
- Keep answers short and practical: 3 to 6 sentences unless asked for more. Plain English; explain any technical term in a few words.
- If the data does not answer the question, say so honestly.
- You are not a doctor. For symptoms, illness or injury, suggest seeing a professional.

--- USER'S DATA ---
{facts}

--- RESEARCH ---
{research_context}
"""

prompt = ChatPromptTemplate.from_messages([
    ("system", SYSTEM_PROMPT),
    MessagesPlaceholder("chat_history"),
    ("human", "{question}"),
])


def _format_docs(docs) -> str:
    if not docs:
        return "No relevant research found."
    return "\n\n".join(doc.page_content for doc in docs)


def _research(question: str) -> str:
    try:
        return _format_docs(_retriever().invoke(question))
    except Exception as e:
        print(f"Research retrieval unavailable: {e}")
        return ("Research retrieval is unavailable right now. Answer from the user's data and "
                "well-established sports science, without citing specific papers.")


def _build_context(x: dict) -> dict:
    facts = (x.get("facts") or "").strip()
    return {
        "facts": facts or "No personal data was sent with this question.",
        "research_context": _research(x["question"]),
        "question": x["question"],
        "chat_history": x["chat_history"],
    }


chain = (
    RunnableLambda(_build_context)
    | prompt
    | llm
    | StrOutputParser()
)
