from fastapi import FastAPI
from pydantic import BaseModel
import app.db as db
from app.extractor import extract_text

app = FastAPI()

class ExtractRequest(BaseModel):
    job_id: int

@app.post("/extract")
def extract(req: ExtractRequest):
    file_path = db.get_file_path(req.job_id)
    text = extract_text(file_path)
    db.save_raw_text(req.job_id, text)
    return {"status": "ok", "job_id": req.job_id}

@app.get("/health")
def health():
    return {"status": "ok"}
