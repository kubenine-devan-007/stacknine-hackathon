from fastapi import FastAPI
from pydantic import BaseModel
import app.db as db
from app.parser import parse_invoice_fields

app = FastAPI()

class ParseRequest(BaseModel):
    job_id: int

@app.post("/parse")
def parse(req: ParseRequest):
    raw_text = db.get_raw_text(req.job_id)
    fields = parse_invoice_fields(raw_text)
    db.save_invoice(req.job_id, fields)
    return {"status": "ok", "job_id": req.job_id}

@app.get("/health")
def health():
    return {"status": "ok"}
