import os, re, shutil, uuid
from pathlib import Path
from fastapi import FastAPI, Request, UploadFile, File, Form, HTTPException
from fastapi.responses import RedirectResponse
from fastapi.templating import Jinja2Templates
import httpx
import app.db as db
from app.config import EXTRACTOR_URL, PARSER_URL, UPLOAD_DIR, S3_BUCKET, ENV

app = FastAPI()
templates = Jinja2Templates(directory="templates")

EMAIL_RE = re.compile(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
HTTP_TIMEOUT = 30.0

@app.on_event("startup")
def startup():
    Path(UPLOAD_DIR).mkdir(parents=True, exist_ok=True)

def current_user(request: Request):
    return request.cookies.get("user_email")

@app.get("/")
def root():
    return RedirectResponse("/login")

@app.get("/login")
def login_page(request: Request):
    return templates.TemplateResponse(request, "login.html", {"error": None})

@app.post("/login")
def login(request: Request, email: str = Form(...), password: str = Form(...)):
    if not EMAIL_RE.match(email):
        return templates.TemplateResponse(request, "login.html", {"error": "Please enter a valid email"})
    response = RedirectResponse("/upload", status_code=302)
    response.set_cookie("user_email", email, httponly=True, samesite="lax")
    return response

@app.get("/logout")
def logout():
    response = RedirectResponse("/login", status_code=302)
    response.delete_cookie("user_email")
    return response

@app.get("/upload")
def upload_page(request: Request):
    email = current_user(request)
    if not email:
        return RedirectResponse("/login", status_code=302)
    return templates.TemplateResponse(request, "upload.html", {"email": email})

@app.post("/upload")
def upload(request: Request, file: UploadFile = File(...)):
    email = current_user(request)
    if not email:
        return RedirectResponse("/login", status_code=302)
    safe_name = f"{uuid.uuid4().hex}_{Path(file.filename).name}"
    if ENV == "production":
        import boto3
        job_id = db.create_job(email, "pending")
        s3_key = f"{job_id}/{safe_name}"
        boto3.client("s3").upload_fileobj(file.file, S3_BUCKET, s3_key)
        db.update_job_file_path(job_id, f"s3://{S3_BUCKET}/{s3_key}")
        # Lambda picks up the S3 event and calls /process/{job_id}
    else:
        dest = os.path.join(UPLOAD_DIR, safe_name)
        with open(dest, "wb") as f:
            shutil.copyfileobj(file.file, f)
        job_id = db.create_job(email, str(Path(dest).resolve()))
        httpx.post(f"http://localhost:8000/process/{job_id}", timeout=HTTP_TIMEOUT)
    return RedirectResponse(f"/results/{job_id}", status_code=302)

@app.post("/process/{job_id}")
def process(job_id: int):
    job = db.get_job(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="Job not found")
    httpx.post(f"{EXTRACTOR_URL}/extract", json={"job_id": job_id, "file_path": job["file_path"]}, timeout=HTTP_TIMEOUT)
    httpx.post(f"{PARSER_URL}/parse",      json={"job_id": job_id}, timeout=HTTP_TIMEOUT)
    return {"status": "ok"}

@app.get("/results/{job_id}")
def results(job_id: int, request: Request):
    email = current_user(request)
    if not email:
        return RedirectResponse("/login", status_code=302)
    job = db.get_job(job_id)
    invoice = db.get_invoice(job_id) if job and job["status"] == "done" else None
    return templates.TemplateResponse(request, "results.html", {
        "job": job, "invoice": invoice,
        "job_id": job_id, "line_items": invoice["line_items"] if invoice else []
    })

@app.get("/history")
def history(request: Request):
    email = current_user(request)
    if not email:
        return RedirectResponse("/login", status_code=302)
    jobs = db.get_jobs_for_user(email)
    return templates.TemplateResponse(request, "history.html", {"jobs": jobs})

@app.get("/health")
def health():
    return {"status": "ok"}
