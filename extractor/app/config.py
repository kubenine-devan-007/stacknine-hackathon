import os

DB_HOST     = os.getenv("DB_HOST", "localhost")
DB_PORT     = int(os.getenv("DB_PORT", "5433"))
DB_NAME     = os.getenv("DB_NAME", "stacknine")
DB_USER     = os.getenv("DB_USER", "postgres")
DB_PASSWORD = os.getenv("DB_PASSWORD", "postgres")
UPLOAD_DIR  = os.getenv("UPLOAD_DIR", "../uploads")
S3_BUCKET   = os.getenv("S3_BUCKET",  "")
