import psycopg2
from app.config import DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD

def get_conn():
    return psycopg2.connect(
        host=DB_HOST, port=DB_PORT,
        dbname=DB_NAME, user=DB_USER, password=DB_PASSWORD
    )

def create_job(user_email: str, file_path: str) -> int:
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO jobs (user_email, file_path, status) VALUES (%s, %s, 'pending') RETURNING id",
                (user_email, file_path)
            )
            job_id = cur.fetchone()[0]
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()
    return job_id

def get_job(job_id: int) -> dict:
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, user_email, file_path, status, created_at FROM jobs WHERE id = %s",
                (job_id,)
            )
            row = cur.fetchone()
    finally:
        conn.close()
    if not row:
        return None
    return {"id": row[0], "user_email": row[1], "file_path": row[2], "status": row[3], "created_at": row[4]}

def update_job_file_path(job_id: int, file_path: str):
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute("UPDATE jobs SET file_path = %s WHERE id = %s", (file_path, job_id))
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()

def get_jobs_for_user(user_email: str) -> list:
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, file_path, status, created_at FROM jobs WHERE user_email = %s ORDER BY created_at DESC",
                (user_email,)
            )
            rows = cur.fetchall()
    finally:
        conn.close()
    return [{"id": r[0], "file_path": r[1], "status": r[2], "created_at": r[3]} for r in rows]

def get_invoice(job_id: int) -> dict:
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, invoice_number, vendor, invoice_date, total FROM invoices WHERE job_id = %s",
                (job_id,)
            )
            row = cur.fetchone()
            if not row:
                return None
            invoice = {
                "id": row[0], "invoice_number": row[1], "vendor": row[2],
                "invoice_date": row[3], "total": row[4]
            }
            cur.execute(
                "SELECT description, amount FROM line_items WHERE invoice_id = %s",
                (invoice["id"],)
            )
            invoice["line_items"] = [{"description": r[0], "amount": r[1]} for r in cur.fetchall()]
    finally:
        conn.close()
    return invoice
