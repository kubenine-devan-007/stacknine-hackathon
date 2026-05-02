import pdfplumber

def extract_text(file_path: str) -> str:
    if file_path.startswith("s3://"):
        import boto3
        from urllib.parse import urlparse
        p = urlparse(file_path)
        local_path = f"/tmp/{p.path.split('/')[-1]}"
        boto3.client("s3").download_file(p.netloc, p.path.lstrip("/"), local_path)
        file_path = local_path

    with pdfplumber.open(file_path) as pdf:
        return "\n".join(page.extract_text() or "" for page in pdf.pages)
