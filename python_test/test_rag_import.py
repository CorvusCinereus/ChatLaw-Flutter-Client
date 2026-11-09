from __future__ import annotations

import sys
from typing import List


OK_MESSAGE = "RAG_CLIENT_TEST_OK"


def run_rag_library_smoke_test() -> str:
    from langchain_core.documents import Document
    from langchain_core.embeddings import Embeddings
    from langchain_community.vectorstores import FAISS
    from langchain_huggingface import HuggingFaceEmbeddings
    import faiss

    class SmokeEmbeddings(Embeddings):
        def embed_documents(self, texts: List[str]) -> List[List[float]]:
            return [self._embed(text) for text in texts]

        def embed_query(self, text: str) -> List[float]:
            return self._embed(text)

        @staticmethod
        def _embed(text: str) -> List[float]:
            value = sum(ord(ch) for ch in text)
            return [
                float(value % 97) / 97.0,
                float(len(text) % 89) / 89.0,
                float(text.lower().count("law")) / 10.0,
                1.0,
            ]

    if not callable(HuggingFaceEmbeddings):
        raise RuntimeError("HuggingFaceEmbeddings is not callable")

    index = faiss.IndexFlatL2(4)
    if index.d != 4:
        raise RuntimeError("FAISS direct import check failed")

    docs = [
        Document(
            page_content="law article smoke test",
            metadata={"source": "rag_client_smoke_test"},
        )
    ]
    vectorstore = FAISS.from_documents(docs, embedding=SmokeEmbeddings())
    results = vectorstore.similarity_search("client calls rag library", k=1)
    if not results or results[0].metadata.get("source") != "rag_client_smoke_test":
        raise RuntimeError("LangChain FAISS similarity_search check failed")

    return OK_MESSAGE


def main() -> int:
    try:
        print(run_rag_library_smoke_test())
        return 0
    except Exception as exc:
        print(f"RAG_CLIENT_TEST_FAILED: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
