import os
import asyncio
from typing import List, Dict, TypedDict, Annotated

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from langchain_community.document_loaders import WebBaseLoader
from langchain_community.vectorstores import FAISS
from langchain_community.embeddings import OllamaEmbeddings
from langchain_community.llms import Ollama
from langchain_text_splitters import RecursiveCharacterTextSplitter
from langchain_core.output_parsers import StrOutputParser
from langchain_core.prompts import PromptTemplate
from langgraph.graph import StateGraph, END

# --- Configuration ---
# Use environment variables or defaults
OLLAMA_BASE_URL = os.environ.get("OLLAMA_HOST", "http://localhost:11434")
MODEL_NAME = "gemma-2-2b-it-lora-sql" # The model created in the Dockerfile
VECTOR_STORE_PATH = "/app/vectorstore" # Persist vector store in the container

# --- FastAPI Setup ---
app = FastAPI(
    title="Ollama Gemma RAG Agent",
    description="A RAG agent using Ollama, Gemma, LangChain, and LangGraph on Cloud Run",
)

# --- LangChain & LangGraph Components Setup ---

def setup_rag_components():
    """Loads data, creates retriever and LLM. Returns retriever and llm."""
    print("Setting up RAG components...")
    # 1. Load Documents
    # Using a sample blog post for demonstration
    print("Loading documents...")
    loader = WebBaseLoader(
        web_paths=("https://lilianweng.github.io/posts/2023-06-23-agent/",),
    )
    docs = loader.load()
    if not docs:
        print("Warning: No documents loaded. RAG will not have context.")
        # Handle case where loading fails or returns empty

    # 2. Split Documents
    print("Splitting documents...")
    text_splitter = RecursiveCharacterTextSplitter(chunk_size=1000, chunk_overlap=200)
    splits = text_splitter.split_documents(docs)

    # 3. Create Embeddings using Ollama
    print(f"Creating Ollama embeddings (model: {MODEL_NAME}, base_url: {OLLAMA_BASE_URL})...")
    # Ensure Ollama server is accessible before proceeding
    embeddings = OllamaEmbeddings(model=MODEL_NAME, base_url=OLLAMA_BASE_URL)

    # 4. Create FAISS Vector Store
    print("Creating FAISS vector store...")
    if os.path.exists(VECTOR_STORE_PATH) and os.listdir(VECTOR_STORE_PATH):
        print(f"Loading existing vector store from {VECTOR_STORE_PATH}")
        vectorstore = FAISS.load_local(VECTOR_STORE_PATH, embeddings, allow_dangerous_deserialization=True)
        # Optional: Add new documents if needed
        # vectorstore.add_documents(splits)
        # vectorstore.save_local(VECTOR_STORE_PATH)
    else:
        print(f"Creating new vector store at {VECTOR_STORE_PATH}")
        if not splits:
             print("Error: Cannot create vector store with no document splits.")
             return None, None # Indicate failure
        vectorstore = FAISS.from_documents(splits, embeddings)
        print(f"Saving vector store to {VECTOR_STORE_PATH}")
        os.makedirs(VECTOR_STORE_PATH, exist_ok=True)
        vectorstore.save_local(VECTOR_STORE_PATH)

    retriever = vectorstore.as_retriever()

    # 5. Initialize Ollama LLM
    print(f"Initializing Ollama LLM (model: {MODEL_NAME}, base_url: {OLLAMA_BASE_URL})...")
    llm = Ollama(model=MODEL_NAME, base_url=OLLAMA_BASE_URL)
    print("RAG components setup complete.")
    return retriever, llm

# --- LangGraph State and Nodes ---

class GraphState(TypedDict):
    """Represents the state of our graph."""
    question: str
    generation: str
    documents: List[str]

# Define nodes
def retrieve(state):
    """Retrieve documents."""
    print("---RETRIEVE--- ")
    question = state["question"]
    documents = retriever.invoke(question)
    print(f"Retrieved {len(documents)} documents.")
    return {"documents": documents, "question": question}

def generate(state):
    """Generate answer."""
    print("---GENERATE--- ")
    question = state["question"]
    documents = state["documents"]
    generation = generation_chain.invoke({"context": documents, "question": question})
    print("Generated response.")
    return {"documents": documents, "question": question, "generation": generation}

def grade_documents(state):
    """Determines whether the retrieved documents are relevant to the question."""
    print("---CHECK DOCUMENT RELEVANCE TO QUESTION--- ")
    question = state["question"]
    documents = state["documents"]

    # Score each doc
    filtered_docs = []
    for d in documents:
        score = grade_documents_chain.invoke({"question": question, "document": d.page_content})
        grade = score.binary_score
        if grade == "yes":
            print("---GRADE: DOCUMENT RELEVANT--- ")
            filtered_docs.append(d)
        else:
            print("---GRADE: DOCUMENT NOT RELEVANT--- ")
            continue
    print(f"Filtered down to {len(filtered_docs)} relevant documents.")
    return {"documents": filtered_docs, "question": question}

# Define conditional edges
def decide_to_generate(state):
    """Determines whether to generate an answer or re-generate the question."""
    print("---ASSESS GRADED DOCUMENTS--- ")
    # documents = state["documents"]

    # if not documents:
    #     # All documents have been filtered check_relevance
    #     # We will re-generate a new query
    #     print("---DECISION: ALL DOCUMENTS ARE NOT RELEVANT TO QUESTION, INCLUDE WEB SEARCH--- ")
    #     return "websearch"
    # else:
        # We have relevant documents, proceed to generation
    print("---DECISION: GENERATE--- ")
    return "generate"

# --- Build Chains and Graph --- 
print("Setting up RAG components...")
retriever, llm = setup_rag_components()

if retriever is None or llm is None:
    print("FATAL: Failed to initialize RAG components. Exiting.")
    # In a real app, handle this more gracefully (e.g., disable RAG endpoint)
    # For Cloud Run, the container might fail to start or become unhealthy.
    # exit(1) # Or raise an exception that FastAPI handles
else:
    print("Components initialized successfully.")
    # Prompt Templates
    prompt = PromptTemplate(
        template="""You are an assistant for question-answering tasks.
        Use the following pieces of retrieved context to answer the question.
        If you don't know the answer, just say that you don't know.
        Use three sentences maximum and keep the answer concise.

        Question: {question}
        Context: {context}
        Answer:""",
        input_variables=["question", "context"],
    )

    # Post-processing
    def format_docs(docs):
        return "\n\n".join(doc.page_content for doc in docs)

    # Chains
    generation_chain = prompt | llm | StrOutputParser()

    # Relevance grading chain
    relevance_prompt = PromptTemplate(
        template="""<|begin_of_text|>><|start_header_id|>system<|end_header_id|>
        You are a grader assessing relevance of a retrieved document to a user question.
        If the document contains keywords related to the user question, grade it as relevant.
        It does not need to be a stringent test. The goal is to filter out erroneous retrievals.

        Give a binary score 'yes' or 'no' score to indicate whether the document is relevant to the question.
        Provide the binary score as a JSON with a single key 'score' and no premable or explanation.

        <|eot_id|><|start_header_id|>user<|end_header_id|>
        Retrieved document: \n {document} \n
        User question: {question} \n
        <|eot_id|><|start_header_id|>assistant<|end_header_id|>
        """,
        input_variables=["question", "document"],
    )

    # Simple Pydantic model for the binary score
    class GradeDocuments(BaseModel):
        """Binary score for document relevance."""
        binary_score: str = Field(description="Documents are relevant to the question, 'yes' or 'no'")

    # Using with_structured_output for JSON parsing (requires latest langchain)
    grade_documents_chain = relevance_prompt | llm | StrOutputParser() # Fallback to string parser if structured fails
    # Note: For structured output with Ollama, ensure the model reliably outputs JSON.
    # Might need more advanced parsing or prompt engineering if Ollama struggles with JSON.
    # For simplicity here, we'll parse the 'yes'/'no' from the string output.
    # A more robust way: grade_documents_chain = relevance_prompt | llm | JsonOutputParser(pydantic_object=GradeDocuments)
    # Update: Let's try a simpler approach first, just checking string output
    def parse_grade_score(output: str) -> GradeDocuments:
        if 'yes' in output.lower():
            return GradeDocuments(binary_score='yes')
        else:
            return GradeDocuments(binary_score='no')

    grade_documents_chain = relevance_prompt | llm | StrOutputParser() | parse_grade_score

    # Build Graph
    print("Building LangGraph workflow...")
    workflow = StateGraph(GraphState)
    workflow.add_node("retrieve", retrieve)
    workflow.add_node("grade_documents", grade_documents)
    workflow.add_node("generate", generate)
    # workflow.add_node("websearch", web_search) # Add if implementing web search

    workflow.set_entry_point("retrieve")
    workflow.add_edge("retrieve", "grade_documents")
    workflow.add_conditional_edges(
        "grade_documents",
        decide_to_generate,
        {
            "generate": "generate",
            # "websearch": "websearch", # Add if implementing web search
        },
    )
    # workflow.add_edge("websearch", "generate") # Add if implementing web search
    workflow.add_edge("generate", END)

    rag_app = workflow.compile()
    print("LangGraph workflow compiled.")

# --- FastAPI Endpoints ---

@app.get("/health", summary="Health Check")
def health_check():
    """Returns a 200 status if the server is running."""
    # Could add checks here for Ollama connection or RAG components readiness
    return {"status": "ok"}

class RAGRequest(BaseModel):
    question: str

class RAGResponse(BaseModel):
    answer: str
    # Add retrieved_documents: List[str] = [] # Optionally return docs

@app.post("/invoke", response_model=RAGResponse, summary="Invoke RAG Agent")
async def invoke_rag(request: RAGRequest):
    """Receives a question and returns the RAG agent's answer."""
    if 'rag_app' not in globals():
         print("Error: RAG application not initialized.")
         raise HTTPException(status_code=500, detail="RAG application failed to initialize")

    inputs = {"question": request.question}
    try:
        print(f"Invoking RAG graph for question: {request.question}")
        # LangGraph runs synchronously by default in its invoke
        # If long-running, consider running in a background thread/task
        # For Cloud Run, keep requests reasonably fast
        response_data = {} # To store final result
        for output in rag_app.stream(inputs):
             for key, value in output.items():
                 print(f"Finished node '{key}':")
                 # Keep track of the last state or specific outputs
                 if key == END:
                     response_data = value # The final state
                 # print(value, sep="\n", flush=True)
        print("---")

        # Extract the final generation
        final_generation = response_data.get('generation', 'No answer generated.')

        # Optional: Log or return retrieved documents
        # final_documents = response_data.get('documents', [])
        # doc_contents = [doc.page_content for doc in final_documents]

        print(f"Final Answer: {final_generation}")
        return RAGResponse(answer=final_generation)

    except Exception as e:
        print(f"Error invoking RAG graph: {e}")
        # Log the full traceback for debugging
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Error processing RAG request: {str(e)}")

if __name__ == "__main__":
    import uvicorn
    # This block is mainly for local development testing
    # Cloud Run will use the command in the Dockerfile/entrypoint.sh
    print("Starting FastAPI server locally for development...")
    # Ensure RAG is set up before starting server if running directly
    if 'rag_app' not in globals():
        print("RAG components not initialized. Run setup manually or ensure Ollama is running.")
    uvicorn.run(app, host="0.0.0.0", port=8080)
