import psycopg2
from app.config import DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD

def get_conn():
    return psycopg2.connect(
        host=DB_HOST, port=DB_PORT,
        dbname=DB_NAME, user=DB_USER, password=DB_PASSWORD
    )

def save_raw_text(job_id: int, content: str):
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO raw_text (job_id, content) VALUES (%s, %s)",
                (job_id, content)
            )
            cur.execute(
                "UPDATE jobs SET status = 'extracted' WHERE id = %s",
                (job_id,)
            )
        conn.commit()
    finally:
        conn.close()

def get_file_path(job_id: int) -> str:
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT file_path FROM jobs WHERE id = %s", (job_id,))
            row = cur.fetchone()
    finally:
        conn.close()
    if not row:
        raise ValueError(f"job {job_id} not found")
    return row[0]
